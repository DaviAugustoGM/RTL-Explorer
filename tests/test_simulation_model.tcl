namespace eval ::svvs::canvas_blocks {
    variable blocks
    array set blocks {}
}
namespace eval ::svvs::canvas_connections {}
namespace eval ::svvs::project_tree { variable projectFiles {} }

proc ::svvs::canvas_connections::exportConnectionData {} {
    return [list [dict create from port:b1:data to port:b2:data width 8]]
}

set root [file dirname [file dirname [file normalize [info script]]]]
source [file join $root src simulation_components.tcl]
source [file join $root src sv_parser.tcl]
source [file join $root src simulation_model.tcl]
if {[::svvs::simulation_components::parseValue 0b1010 bin] ne {1 10}} { error "binary input parsing failed" }
if {[::svvs::simulation_components::parseValue 0x2A hex] ne {1 42}} { error "hex input parsing failed" }
if {[::svvs::simulation_components::formatValue 10 8 bin] ne {0b00001010}} { error "binary formatting failed" }
if {[::svvs::simulation_components::formatValue 10 8 hex] ne {0x0A}} { error "hex formatting failed" }
foreach {literal expected} {0b10 2 0x2 2 2 2} {
    set parsed [::svvs::simulation_components::parseMappedValue $literal]
    if {![lindex $parsed 0] || [lindex $parsed 1] != $expected} {
        error "mapped value parsing failed for $literal"
    }
}
set valueMap [dict create 0 IDLE 2 WRITE]
if {[::svvs::simulation_components::formatMappedValue 2 2 hex $valueMap] ne "WRITE"} {
    error "mapped output text was not displayed"
}
if {[::svvs::simulation_components::formatMappedValue 1 2 hex $valueMap] ne "0x1"} {
    error "unmapped output did not fall back to its number format"
}
set enum [lindex [::svvs::sv_parser::enumDefinitionsFromText \
    {typedef enum logic [2:0] {IDLE = 3'b000, RUN = 3'b011, DONE} state_t;}] 0]
if {[dict get $enum values RUN] != 3 || [dict get $enum values DONE] != 4} {
    error "FSM enum values were not preserved"
}

set commentedHeader {
module memory_tester (
  input logic clk,
  input logic rst, // comment after a comma
  output logic mem_rst, /* block comment after a comma */
  output logic mem_read,
  output logic mem_write,
  output logic [1:0] addr
);
endmodule
}
set parsedPorts [::svvs::sv_parser::portsFromModuleText $commentedHeader memory_tester]
set parsedNames {}
foreach port $parsedPorts { lappend parsedNames [dict get $port name] }
if {$parsedNames ne {clk rst mem_rst mem_read mem_write addr}} {
    error "comments in an ANSI module header hid ports: $parsedNames"
}
if {[dict get [lindex $parsedPorts end] width] != 2} {
    error "port width after comments was not parsed"
}

set producer [dict create name producer instance u_producer ports [list \
    [dict create name data direction output width 8]]]
set consumer [dict create name consumer instance u_consumer ports [list \
    [dict create name data direction input width 8]]]
set ::svvs::canvas_blocks::blocks(b1) [dict create module $producer]
set ::svvs::canvas_blocks::blocks(b2) [dict create module $consumer]

set model [::svvs::simulation_model::diagramModel]
if {[llength [dict get $model errors]] != 0} { error [dict get $model errors] }
if {[llength [dict get $model inputs]] != 0} { error "connected input became external" }
if {[llength [dict get $model outputs]] != 1} { error "output probe was not exported" }
if {[::svvs::simulation_model::widthDecl 8] ne {[7:0] }} { error "invalid width declaration" }

set target [file join [file dirname [info script]] generated_top.sv]
::svvs::simulation_model::writeTop $target $model
set handle [open $target r]
set generated [read $handle]
close $handle
file delete $target
if {![string match {*producer u_producer*} $generated]} { error "producer instance missing" }
if {![string match {*consumer u_consumer*} $generated]} { error "consumer instance missing" }
puts "simulation model tests: ok"
