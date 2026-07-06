set root [file dirname [file dirname [file normalize [info script]]]]
source [file join $root tests test_yosys_flow.tcl]
source [file join $root src simulation_backends.tcl]

foreach engine {CXXRTL Icarus Python Automatic} {
    set ::svvs::simulation_backends::selectedEngine $engine
    set backend [::svvs::simulation_backends::prepare $result]
    if {![dict get $backend ok]} {
        error "$engine backend preparation failed: [dict get $backend message]"
    }
    set command [linsert [dict get $backend command] 0 |]
    set channel [open $command r+]
    fconfigure $channel -buffering line -encoding utf-8
    if {[gets $channel ready] < 0 || ![string match "READY*" $ready]} {
        error "$engine backend did not become ready: $ready"
    }
    if {[gets $channel values] < 0 || ![string match "VALUES*" $values]} {
        error "$engine backend did not emit values: $values"
    }
    puts $channel "EVAL"
    flush $channel
    if {[gets $channel values] < 0 || ![string match "VALUES*" $values]} {
        error "$engine backend did not evaluate: $values"
    }
    puts $channel "SET\tu_consumer__clk\t1"
    flush $channel
    if {[gets $channel values] < 0 || [string first "u_consumer__clk=1" $values] < 0} {
        error "$engine backend did not apply an input: $values"
    }
    if {$engine eq "CXXRTL"} {
        puts $channel "WATCH\t__watch\tproducer\tdata"
        flush $channel
        if {[gets $channel values] < 0 || [string first "__watch=" $values] < 0} {
            error "CXXRTL backend did not expose an internal watch: $values"
        }
        puts $channel "WATCH\t__missing\tmodule_not_in_diagram\tstate"
        flush $channel
        if {[gets $channel errorLine] < 0 || ![string match "ERROR*" $errorLine]} {
            error "CXXRTL backend did not report a missing watch: $errorLine"
        }
        puts $channel "EVAL"
        flush $channel
        if {[gets $channel values] < 0 || ![string match "VALUES*" $values]} {
            error "a missing CXXRTL watch stopped the backend: $values"
        }
    }
    puts $channel "QUIT"
    flush $channel
    catch {close $channel}
}

puts "simulation backend tests: ok"
