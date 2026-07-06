set root [file dirname [file dirname [file normalize [info script]]]]
set ::APP_DIR [file join $root src]

namespace eval ::svvs::canvas_blocks {
    variable blocks
    array set blocks {}
}
namespace eval ::svvs::project_tree {
    variable fsms {}
}

source [file join $root src simulator_view.tcl]

set memory [dict create name memory instance u_memory ports {}]
set ::svvs::canvas_blocks::blocks(memory) [dict create module $memory]
set ::svvs::project_tree::fsms [list \
    [dict create module control_unit stateVariable current_state] \
    [dict create module memory stateVariable memory_state]]

set ::sentWatches {}
rename ::svvs::simulator_view::send ::svvs::simulator_view::realSend
proc ::svvs::simulator_view::send {args} {
    lappend ::sentWatches $args
    return 1
}

::svvs::simulator_view::initializeFsmWatches
if {[llength $::sentWatches] != 1 ||
        [lindex [lindex $::sentWatches 0] 2] ne "memory"} {
    error "FSMs outside the block diagram were watched: $::sentWatches"
}

puts "FSM watch filter test: ok"
