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
set typedHeader {
module typed_ports (
  input logic [7:0] a, b,
  output vending_pkg::state_t state,
  output logic done
);
endmodule
}
set typedPorts [::svvs::sv_parser::portsFromModuleText $typedHeader typed_ports]
set typedNames {}
foreach port $typedPorts { lappend typedNames [dict get $port name] }
if {$typedNames ne {a b state done} || [dict get [lindex $typedPorts 1] width] != 8} {
    error "package-typed or grouped ANSI ports were parsed incorrectly: $typedNames"
}
set bodyParenHeader {
module body_parens #(
  parameter int WIDTH = (2 + 2)
) (
  input logic clk,
  output pkg::state_t state,
  output logic change_load
);
logic internal;
always_comb begin
  if (internal) change_load = fn(a, b);
end
endmodule
}
set bodyPorts [::svvs::sv_parser::portsFromModuleText $bodyParenHeader body_parens]
set bodyNames {}
foreach port $bodyPorts { lappend bodyNames [dict get $port name] }
if {$bodyNames ne {clk state change_load}} {
    error "module body parentheses were mistaken for ports: $bodyNames"
}
set parameterHeader {
module aclint_top #(
  parameter int HARTS      = 2,
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
) (
  input  logic                  clock,
  input  logic [ADDR_WIDTH-1:0] addr_i,
  input  logic [DATA_WIDTH-1:0] wdata_i,
  output logic [DATA_WIDTH-1:0] rdata_o,
  output logic [HARTS-1:0]      msip_o
);
endmodule
}
set parameterPorts [::svvs::sv_parser::portsFromModuleText $parameterHeader aclint_top]
set parameterWidths {}
foreach port $parameterPorts {
    dict set parameterWidths [dict get $port name] [dict get $port width]
}
if {[dict get $parameterWidths clock] != 1 ||
    [dict get $parameterWidths addr_i] != 32 ||
    [dict get $parameterWidths wdata_i] != 32 ||
    [dict get $parameterWidths rdata_o] != 32 ||
    [dict get $parameterWidths msip_o] != 2} {
    error "parameterized port widths were parsed incorrectly: $parameterWidths"
}
if {[::svvs::sv_parser::evalIntExpression {(HARTS <= 1) ? 1 : $clog2(HARTS)} \
        [dict create HARTS 4]] != 2} {
    error "parameter expression with clog2 was not evaluated"
}
set classicVerilog {
module legacy_counter(clk, rst, en, count, done);
  input clk;
  input rst, en;
  output reg [3:0] count;
  output done;
endmodule
}
set classicPorts [::svvs::sv_parser::portsFromModuleText $classicVerilog legacy_counter]
set classicNames {}
foreach port $classicPorts { lappend classicNames [dict get $port name] }
if {$classicNames ne {clk rst en count done}} {
    error "classic Verilog ports were not parsed in header order: $classicNames"
}
if {[dict get [lindex $classicPorts 3] direction] ne "output" ||
    [dict get [lindex $classicPorts 3] width] != 4} {
    error "classic Verilog output reg width was not parsed"
}
set bodyOnlyVerilog {
module loose_counter;
  parameter WIDTH = 4;
  input wire clk;
  input wire rst;
  input wire [WIDTH-1:0] step;
  output reg [WIDTH-1:0] count;
  output wire done;
endmodule
}
set bodyOnlyPorts [::svvs::sv_parser::portsFromModuleText $bodyOnlyVerilog loose_counter]
set bodyOnlyNames {}
set bodyOnlyWidths {}
foreach port $bodyOnlyPorts {
    lappend bodyOnlyNames [dict get $port name]
    dict set bodyOnlyWidths [dict get $port name] [dict get $port width]
}
if {$bodyOnlyNames ne {clk rst step count done}} {
    error "Verilog body port declarations were not parsed: $bodyOnlyNames"
}
if {[dict get $bodyOnlyWidths step] != 4 || [dict get $bodyOnlyWidths count] != 4} {
    error "Verilog body parameterized port widths were not parsed: $bodyOnlyWidths"
}
set structuralVerilog {
module source(input clk, output [7:0] data);
endmodule
module sink(input clk, input [7:0] data);
endmodule
module top(input clk);
  wire [7:0] bus;
  source u_source(
    .clk(clk),
    .data(bus)
  );
  sink u_sink(
    .clk(clk),
    .data(bus)
  );
endmodule
}
set structuralPath [file join [file dirname [info script]] structural_fixture.v]
set fh [open $structuralPath w]
puts $fh $structuralVerilog
close $fh
set structuralHints [::svvs::sv_parser::structuralConnectionsFromFiles \
    [list $structuralPath] {source sink}]
file delete $structuralPath
set foundStructural 0
foreach hint $structuralHints {
    if {[dict get $hint fromModule] eq "source" &&
        [dict get $hint fromPort] eq "data" &&
        [dict get $hint toModule] eq "sink" &&
        [dict get $hint toPort] eq "data"} {
        set foundStructural 1
    }
}
if {!$foundStructural} {
    error "structural instance connections were not detected: $structuralHints"
}
set positionalVerilog {
module pos_source(clk, data);
  input clk;
  output [7:0] data;
endmodule
module pos_sink(clk, data);
  input clk;
  input [7:0] data;
endmodule
module pos_top(input clk);
  wire [7:0] bus;
  pos_source u_source(clk, bus);
  pos_sink u_sink(clk, bus);
endmodule
}
set positionalPath [file join [file dirname [info script]] positional_fixture.v]
set fh [open $positionalPath w]
puts $fh $positionalVerilog
close $fh
set positionalHints [::svvs::sv_parser::structuralConnectionsFromFiles \
    [list $positionalPath] {pos_source pos_sink}]
file delete $positionalPath
set foundPositional 0
foreach hint $positionalHints {
    if {[dict get $hint fromModule] eq "pos_source" &&
        [dict get $hint fromPort] eq "data" &&
        [dict get $hint toModule] eq "pos_sink" &&
        [dict get $hint toPort] eq "data"} {
        set foundPositional 1
    }
}
if {!$foundPositional} {
    error "positional structural instance connections were not detected: $positionalHints"
}
set slicedVerilog {
module wide_source(output [15:0] data);
endmodule
module byte_sink(input [7:0] data);
endmodule
module sliced_top;
  wire [15:0] bus;
  wide_source u_source(.data(bus));
  byte_sink u_low(.data(bus[7:0]));
  byte_sink u_high(.data(bus[15:8]));
endmodule
}
set slicedPath [file join [file dirname [info script]] sliced_fixture.v]
set fh [open $slicedPath w]
puts $fh $slicedVerilog
close $fh
set slicedHints [::svvs::sv_parser::structuralConnectionsFromFiles \
    [list $slicedPath] {wide_source byte_sink}]
file delete $slicedPath
set foundLowSlice 0
set foundHighSlice 0
foreach hint $slicedHints {
    if {[dict get $hint fromModule] eq "wide_source" &&
        [dict get $hint fromPort] eq "data" &&
        [dict get $hint toModule] eq "byte_sink" &&
        [dict get $hint toPort] eq "data"} {
        if {[dict get $hint toRange] eq "7:0"} { set foundLowSlice 1 }
        if {[dict get $hint toRange] eq "15:8"} { set foundHighSlice 1 }
    }
}
if {!$foundLowSlice || !$foundHighSlice} {
    error "sliced structural connections were not detected: $slicedHints"
}

set mapPath [file join [file dirname [info script]] value_map_fixture.txt]
set fh [open $mapPath w]
puts $fh {[addr]
0x0 = First item
3 = Fourth item
[ready]
1 = Ready}
close $fh
set parsedMaps [::svvs::simulation_components::parseValueMapFile $mapPath]
file delete $mapPath
if {[dict get $parsedMaps addr 3] ne "Fourth item" ||
    [dict get $parsedMaps ready 1] ne "Ready"} {
    error "value map file was not parsed"
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

array unset ::svvs::canvas_blocks::blocks
array set ::svvs::canvas_blocks::blocks {}
set wideSource [dict create name wide_source instance u_wide ports [list \
    [dict create name data direction output width 16]]]
set lowSink [dict create name byte_sink instance u_low ports [list \
    [dict create name data direction input width 8]]]
set highSink [dict create name byte_sink instance u_high ports [list \
    [dict create name data direction input width 8]]]
set ::svvs::canvas_blocks::blocks(ws) [dict create module $wideSource]
set ::svvs::canvas_blocks::blocks(lo) [dict create module $lowSink]
set ::svvs::canvas_blocks::blocks(hi) [dict create module $highSink]
proc ::svvs::canvas_connections::exportConnectionData {} {
    return [list \
        [dict create from port:ws:data to port:lo:data width 8 fromRange 7:0 toRange ""] \
        [dict create from port:ws:data to port:hi:data width 8 fromRange 15:8 toRange ""]]
}
set slicedModel [::svvs::simulation_model::diagramModel]
if {[llength [dict get $slicedModel errors]] != 0} { error [dict get $slicedModel errors] }
if {[llength [dict get $slicedModel inputs]] != 0} {
    error "slice-driven sink became an external input"
}
if {[llength [dict get $slicedModel sliceAssignments]] != 2} {
    error "sliced assignments were not modeled"
}
set slicedTarget [file join [file dirname [info script]] generated_sliced_top.sv]
::svvs::simulation_model::writeTop $slicedTarget $slicedModel
set handle [open $slicedTarget r]
set slicedGenerated [read $handle]
close $handle
file delete $slicedTarget
if {![regexp {assign net_[0-9]+ = net_[0-9]+\[7:0\];} $slicedGenerated] ||
    ![regexp {assign net_[0-9]+ = net_[0-9]+\[15:8\];} $slicedGenerated]} {
    error "sliced assignments missing from generated top: $slicedGenerated"
}
puts "simulation model tests: ok"
