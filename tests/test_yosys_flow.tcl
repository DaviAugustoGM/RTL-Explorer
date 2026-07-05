set root [file dirname [file dirname [file normalize [info script]]]]
set ::APP_DIR [file join $root src]
namespace eval ::svvs::canvas_blocks { variable blocks; array set blocks {} }
namespace eval ::svvs::canvas_connections {}
namespace eval ::svvs::project_tree {
    variable projectFiles [list \
        [file join $::root sample producer.sv] \
        [file join $::root sample consumer.sv]]
}
proc ::svvs::canvas_connections::exportConnectionData {} {
    set result {}
    foreach pair {
        {port:p:clk port:c:clk 1}
        {port:p:rst_n port:c:rst_n 1}
        {port:p:data port:c:data 8}
        {port:p:valid port:c:valid 1}
    } {
        lassign $pair from to width
        lappend result [dict create from $from to $to width $width]
    }
    return $result
}
source [file join $root src simulation_components.tcl]
source [file join $root src simulation_model.tcl]

set producer [dict create name producer instance u_producer ports [list \
    [dict create name clk direction input width 1] \
    [dict create name rst_n direction input width 1] \
    [dict create name enable direction input width 1] \
    [dict create name data direction output width 8] \
    [dict create name valid direction output width 1]]]
set consumer [dict create name consumer instance u_consumer ports [list \
    [dict create name clk direction input width 1] \
    [dict create name rst_n direction input width 1] \
    [dict create name data direction input width 8] \
    [dict create name valid direction input width 1] \
    [dict create name ready direction output width 1]]]
set ::svvs::canvas_blocks::blocks(p) [dict create module $producer]
set ::svvs::canvas_blocks::blocks(c) [dict create module $consumer]

set result [::svvs::simulation_model::prepare]
if {![dict get $result ok]} { error [dict get $result message] }
if {![file exists [dict get $result json]]} { error "netlist JSON was not generated" }
puts "yosys flow test: ok"
