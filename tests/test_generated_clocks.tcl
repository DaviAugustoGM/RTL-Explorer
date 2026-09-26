set root [file dirname [file dirname [file normalize [info script]]]]
set ::APP_DIR [file join $root src]
source [file join $::APP_DIR simulation_components.tcl]
source [file join $::APP_DIR simulation_model.tcl]
source [file join $::APP_DIR simulation_backends.tcl]
set directory [file join $root .rtl_explorer_build generated_clocks_[pid]]
file mkdir $directory

proc exchange {channel command} {
    puts $channel $command
    flush $channel
    if {[gets $channel line] < 0 || ![string match "VALUES*" $line]} {
        error "Unexpected backend response to $command: $line"
    }
    set values {}
    foreach field [lrange [split $line \t] 1 end] {
        lassign [split $field =] name value
        dict set values $name $value
    }
    return $values
}

foreach scenario {{0 Automatic} {1 Automatic} {1 Icarus}} {
    lassign $scenario internal selectedEngine
    set source [string map [list @CLOCK@ [expr {$internal ? "tick" : "clk"}] \
        @CASCADE_CLOCK@ [expr {$internal ? "tick2" : "clk"}]] {
module rtl_explorer_top(input clk, rst, output reg tick,
    output reg [3:0] count, falling, cascade, captured, previous);
    reg tick2;
    reg [3:0] data;
    always @(posedge clk or posedge rst)
        if (rst) data <= 0; else data <= data + 1;
    always @(posedge clk or posedge rst)
        if (rst) tick <= 0; else tick <= ~tick;
    always @(posedge @CLOCK@ or posedge rst)
        if (rst) count <= 0; else count <= count + 1;
    always @(posedge @CLOCK@ or posedge rst)
        if (rst) begin captured <= 0; previous <= 0; end
        else begin captured <= data; previous <= count; end
    always @(negedge @CLOCK@ or posedge rst)
        if (rst) falling <= 0; else falling <= falling + 1;
    always @(posedge @CLOCK@ or posedge rst)
        if (rst) tick2 <= 0; else tick2 <= ~tick2;
    always @(posedge @CASCADE_CLOCK@ or posedge rst)
        if (rst) cascade <= 0; else cascade <= cascade + 1;
endmodule
}]
    set converted [file join $directory design.v]
    set json [file join $directory netlist.json]
    set cxxrtl [file join $directory cxxrtl_model.cpp]
    set handle [open $converted w]
    puts $handle $source
    close $handle
    set commands [list \
        "read_verilog [::svvs::simulation_model::yosysQuote $converted]" \
        {hierarchy -check -top rtl_explorer_top} \
        {proc; flatten; opt; memory; opt} \
        "write_json [::svvs::simulation_model::yosysQuote $json]" \
        "write_cxxrtl -O3 -g2 [::svvs::simulation_model::yosysQuote $cxxrtl]"]
    exec [::svvs::toolchain::yosys] -Q -T -p [join $commands {; }] 2>@1
    set model [dict create inputs [list \
        [dict create name clk width 1] [dict create name rst width 1]] \
        outputs [list [dict create name tick width 1] [dict create name count width 4]]]
    foreach name {falling cascade captured previous} {
        dict lappend model outputs [dict create name $name width 4]
    }
    set result [dict create model $model json $json cxxrtl $cxxrtl converted $converted]
    if {$internal} {
        foreach engine {Python} {
            set ::svvs::simulation_backends::selectedEngine $engine
            set rejected [::svvs::simulation_backends::prepare $result]
            if {[dict get $rejected ok] || ![string match {*Icarus*} [dict get $rejected message]]} {
                error "$engine accepted an unsupported generated clock"
            }
        }
    }
    set ::svvs::simulation_backends::selectedEngine $selectedEngine
    set backend [::svvs::simulation_backends::prepare $result]
    set expectedEngine [expr {$selectedEngine eq "Icarus" ? "Icarus" : "CXXRTL"}]
    if {![dict get $backend ok] || [dict get $backend engine] ne $expectedEngine} {
        error "Expected $expectedEngine: $backend"
    }
    set channel [open [linsert [dict get $backend command] 0 |] r+]
    fconfigure $channel -buffering line
    try {
        gets $channel ready
        if {![string match "READY*" $ready]} { error "Backend not ready: $ready" }
        gets $channel initial
        exchange $channel "SET\trst\t1"
        exchange $channel "SET\trst\t0"
        for {set cycle 1} {$cycle <= 6} {incr cycle} {
            set values [exchange $channel "SET\tclk\t1"]
            set expected [expr {$internal ? ($cycle + 1) / 2 : $cycle}]
            if {[dict get $values count] != $expected} {
                error "$expectedEngine missed or duplicated an edge at cycle $cycle: $values"
            }
            set expectedData [expr {$internal ? 2 * $expected - 1 : $cycle - 1}]
            set expectedFalling [expr {$internal ? $cycle / 2 : $cycle - 1}]
            foreach name {captured previous falling cascade} expectedValue [list \
                $expectedData [expr {$expected - 1}] $expectedFalling \
                [expr {$internal ? ($expected + 1) / 2 : $cycle}]] {
                if {[dict get $values $name] != $expectedValue} {
                    error "$expectedEngine: $name expected $expectedValue at cycle $cycle: $values"
                }
            }
            set values [exchange $channel EVAL]
            if {[dict get $values count] != $expected} { error "EVAL introduced an edge" }
            set values [exchange $channel "SET\tclk\t0"]
            if {[dict get $values count] != $expected} { error "Falling edge changed the counter" }
        }
        set values [exchange $channel "SET\trst\t1"]
        foreach name {count falling cascade captured previous} {
            if {[dict get $values $name] != 0} { error "Reset did not clear $name: $values" }
        }
    } finally {
        catch {puts $channel QUIT; flush $channel}
        close $channel
    }
    puts "$expectedEngine clock regression: ok"
}
