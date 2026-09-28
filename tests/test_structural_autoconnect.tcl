set root [file dirname [file dirname [file normalize [info script]]]]
source [file join $root src sv_parser.tcl]
source [file join $root src canvas_connections.tcl]
namespace eval ::svvs::console { variable messages {} }
proc ::svvs::console::log {message args} { lappend ::svvs::console::messages $message }
namespace eval ::svvs::project_tree { variable projectFiles {} }
namespace eval ::svvs::canvas_blocks {
    variable modules; array set modules {}
    variable tagToPort; array set tagToPort {}
    variable tagToBlock; array set tagToBlock {}
}
proc ::svvs::canvas_blocks::portInfo {tag} {
    return [dict create module $::svvs::canvas_blocks::modules($::svvs::canvas_blocks::tagToBlock($tag)) \
        port $::svvs::canvas_blocks::tagToPort($tag)]
}
proc ::svvs::canvas_blocks::portCenter {tag} { return {0 0} }
proc ::svvs::canvas_connections::portIsLive {tag} { return 1 }
proc ::svvs::canvas_connections::removeDangling {} {}
proc ::svvs::canvas_connections::drawConnection {from to {width 1} {fromRange ""} {toRange ""}} {
    variable seq
    variable connections
    set id "conn:[incr seq]"
    set connections($id) [dict create from $from to $to width $width fromRange $fromRange toRange $toRange]
    return $id
}
proc connected {a b} {
    return [expr {$b in [dict get [::svvs::canvas_connections::fullPortComponent $a] ports]}]
}
set text {
module mux2x1(input [9:0] in1, in2, input sel, output [9:0] out); endmodule
module tick_gen(input clk, rst, input [9:0] max, incr, output tick); endmodule
module uart_tx(input tick, stop_size, input [2:0] data_size, input [1:0] parity, output start); endmodule
module uart_rx(input tick, stop_size, input [2:0] data_size, input [1:0] parity, output start); endmodule
module uart(input clk, rst, stop_size, input [2:0] data_size, input [1:0] parity,
            input [9:0] clkbit, oversample);
    wire start_tx, start_rx, tick_tx, tick_rx;
    wire [9:0] incr_tick_tx;
    mux2x1 mux_tx(.in1(clkbit), .in2(10'd1), .sel(start_tx), .out(incr_tick_tx));
    tick_gen tick_gen1(.clk(clk), .rst(rst), .max(clkbit), .incr(incr_tick_tx), .tick(tick_tx));
    tick_gen tick_gen2(.clk(clk), .rst(rst), .max(clkbit), .incr(oversample), .tick(tick_rx));
    uart_tx utx(.tick(tick_tx), .stop_size(stop_size), .data_size(data_size), .parity(parity), .start(start_tx));
    uart_rx urx(.tick(tick_rx), .stop_size(stop_size), .data_size(data_size), .parity(parity), .start(start_rx));
endmodule
module unrelated(input clk);
    tick_gen alien(.clk(clk), .rst(clk), .max(), .incr(), .tick());
endmodule
}
set directory [file join $root .rtl_explorer_build structural_autoconnect_[pid]]
file mkdir $directory
set path [file join $directory fixture.sv]
set handle [open $path w]; puts $handle $text; close $handle
set ::svvs::project_tree::projectFiles [list $path]
set names {mux2x1 tick_gen uart_tx uart_rx}
set instances [::svvs::sv_parser::structuralInstantiationsFromFiles [list $path] "" $names]
if {[llength $instances] != 6} { error "Module boundaries mixed unrelated instances: $instances" }
foreach inst $instances {
    set type [dict get $inst type]
    set id [dict get $inst instance]
    set module [dict create name $type instance $id structuralOwner [dict get $inst owner]]
    set ::svvs::canvas_blocks::modules($id) $module
    foreach port [::svvs::sv_parser::portsFromModuleText $text $type] {
        set tag "$id.[dict get $port name]"
        set ::svvs::canvas_blocks::tagToBlock($tag) $id
        set ::svvs::canvas_blocks::tagToPort($tag) $port
    }
}
set created [::svvs::canvas_connections::autoConnect]
foreach pair {
    {tick_gen1.clk tick_gen2.clk}
    {tick_gen1.rst tick_gen2.rst}
    {tick_gen1.max tick_gen2.max}
    {mux_tx.in1 tick_gen1.max}
    {utx.stop_size urx.stop_size}
    {utx.data_size urx.data_size}
    {utx.parity urx.parity}
    {utx.start mux_tx.sel}
    {mux_tx.out tick_gen1.incr}
    {tick_gen1.tick utx.tick}
    {tick_gen2.tick urx.tick}
} {
    if {![connected {*}$pair]} { error "Missing connection: $pair" }
}
foreach pair {{tick_gen1.tick tick_gen2.tick} {alien.clk tick_gen1.clk} {utx.start urx.start} {mux_tx.in2 mux_tx.in1}} {
    if {[connected {*}$pair]} { error "Unexpected connection: $pair" }
}
if {[::svvs::canvas_connections::autoConnect] != 0} { error "Repeated Auto Connect duplicated wires" }

# Equivalent positional maps must retain instance identity and skip the constant.
set positional [string map [list \
    {.in1(clkbit), .in2(10'd1), .sel(start_tx), .out(incr_tick_tx)} \
    {clkbit, 10'd1, start_tx, incr_tick_tx}] $text]
set handle [open $path w]; puts $handle $positional; close $handle
array unset ::svvs::canvas_connections::connections
::svvs::canvas_connections::autoConnect
if {![connected utx.start mux_tx.sel] || ![connected mux_tx.out tick_gen1.incr]} {
    error "Positional mux connections were not preserved"
}

# Do not merge two user-driven inputs even if the HDL describes a shared net.
array unset ::svvs::canvas_connections::connections
::svvs::canvas_connections::drawConnection utx.start tick_gen1.clk
::svvs::canvas_connections::drawConnection urx.start tick_gen2.clk
::svvs::canvas_connections::autoConnect
if {[connected tick_gen1.clk tick_gen2.clk]} { error "Separate drivers were shorted together" }

# Reject the mixed syntax from the report instead of accepting a partial port map.
set invalid [string map [list \
    {.in1(clkbit), .in2(10'd1), .sel(start_tx), .out(incr_tick_tx)} \
    {.in1(clk), in2(1'b1), start_tx, incr_tick_tx}] $text]
set handle [open $path w]; puts $handle $invalid; close $handle
array unset ::svvs::canvas_connections::connections
::svvs::canvas_connections::autoConnect
if {[connected utx.start mux_tx.sel] || [connected mux_tx.in1 tick_gen1.clk]} {
    error "Invalid mux declaration was partly connected"
}
if {![string match {*uart.mux_tx*misturadas*} [join $::svvs::console::messages \n]]} {
    error "Missing mixed-syntax warning"
}
puts "structural autoconnect tests: ok ($created connections)"
