set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "$message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]
proc assert {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc clickSwitch {id bit} {
    set canvas $::svvs::canvas_blocks::canvas
    lassign [$canvas coords "switch-knob:$id:$bit"] x1 y1 x2 y2
    set x [expr {int(($x1 + $x2) / 2 - [$canvas canvasx 0])}]
    set y [expr {int(($y1 + $y2) / 2 - [$canvas canvasy 0])}]
    event generate $canvas <Motion> -x $x -y $y
    event generate $canvas <ButtonPress-1> -x $x -y $y
    event generate $canvas <ButtonRelease-1> -x $x -y $y
    update
}
proc testSwitch {} {
    set template [::svvs::simulation_components::templateByKind switch]
    assert {$template ne ""} "Switch missing from built-ins"
    set id [::svvs::canvas_blocks::drawBlock $template 250 150]
    set canvas $::svvs::canvas_blocks::canvas
    update
    set original [$canvas coords "switch-lever:$id:0"]
    clickSwitch $id 0
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    assert {[dict get $module simulationConfig value] == 1} "Click did not turn switch on"
    assert {[$canvas coords "switch-lever:$id:0"] ne $original} "Lever did not move"
    clickSwitch $id 0
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    assert {[dict get $module simulationConfig value] == 0} "Second click did not turn switch off"
    assert {[$canvas coords "switch-lever:$id:0"] eq $original} "Lever did not return"
    ::svvs::simulation_components::setPortWidth "port:$id:out" 4
    assert {[llength [$canvas find withtag "switch-track:$id"]] == 4} "Switch bank did not resize"
    clickSwitch $id 3
    clickSwitch $id 0
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    assert {[dict get $module simulationConfig value] == 9} "Bits did not toggle independently"
    set led [::svvs::canvas_blocks::drawBlock [::svvs::simulation_components::templateByKind led] 500 150]
    ::svvs::canvas_connections::drawConnection "port:$id:out" "port:$led:in"
    assert {[::svvs::canvas_connections::portWidth "port:$led:in"] == 4} "LED did not adopt switch width"
    set model [::svvs::simulation_model::diagramModel]
    set signal [dict get [lindex [dict get $model inputs] 0] name]
    assert {[dict get [lindex [dict get $model inputs] 0] initialValue] == 9} "Switch initial value missing"
    ::svvs::simulation_components::showMenu $id 0 0 0
    assert {[.signalBlockMenu entrycget 0 -label] eq "Rename..."} "Switch context menu missing"
    ::svvs::diagram_simulation::activate $model
    clickSwitch $id 1
    assert {$::svvs::simulator_view::signalVars($signal) == 11} "Live click did not send source value"
    ::svvs::diagram_simulation::updateValues [list "$signal=11"]
    assert {[$canvas itemcget "led-bit:$led:1" -fill] eq "#ff3434"} "LED did not receive switch value"
    ::svvs::diagram_simulation::deactivate
    set data [::svvs::canvas_blocks::exportDiagramData]
    ::svvs::canvas_blocks::clearCanvas
    ::svvs::canvas_blocks::importDiagramData $data
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    assert {[dict get $module simulationConfig value] == 11} "Switch state lost on reload"
    assert {[llength [$canvas find withtag "switch-track:$id"]] == 4} "Switch bank lost on reload"
    set sink [dict create name sink instance sink ports [list [dict create name in direction input width 8]]]
    set sinkId [::svvs::canvas_blocks::drawBlock $sink 550 350]
    set automatic [::svvs::canvas_blocks::drawBlock $template 250 350]
    set conn [::svvs::canvas_connections::drawConnection "port:$automatic:out" "port:$sinkId:in"]
    assert {[llength [$canvas find withtag "switch-track:$automatic"]] == 8} "Connection did not adapt switch bank"
    set ::svvs::canvas_connections::rangeEditConn $conn
    set ::svvs::canvas_connections::rangeEditFrom ""
    set ::svvs::canvas_connections::rangeEditTo 6:4
    ::svvs::canvas_connections::commitRangeDialog
    assert {[llength [$canvas find withtag "switch-track:$automatic"]] == 3} "Connection range did not adapt switch bank"
    set before [$canvas coords "switch-lever:$id:0"]
    ::svvs::diagram_simulation::activate [::svvs::simulation_model::diagramModel]
    ::svvs::simulation_components::showMenu $id 0 0 0
    assert {[.signalBlockMenu.switchRaisedValue index end] == 1} "Switch polarity options missing"
    .signalBlockMenu.switchRaisedValue invoke 1
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    assert {[dict get $module simulationConfig raisedValue] == 0} "Menu did not set raised output to zero"
    assert {[dict get $module simulationConfig value] == 4} "Polarity did not invert all four output bits"
    assert {[$canvas coords "switch-lever:$id:0"] eq $before} "Polarity changed lever position"
    assert {$::svvs::simulator_view::signalVars($signal) == 4} "Polarity did not update live output"
    clickSwitch $id 0
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    assert {[dict get $module simulationConfig value] == 5} "Lowered active-low switch did not send one"
    clickSwitch $id 0
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    assert {[dict get $module simulationConfig value] == 4} "Raised active-low switch did not send zero"
    ::svvs::diagram_simulation::deactivate
    set data [::svvs::canvas_blocks::exportDiagramData]
    ::svvs::canvas_blocks::clearCanvas
    ::svvs::canvas_blocks::importDiagramData $data
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    assert {[dict get $module simulationConfig raisedValue] == 0} "Switch polarity lost on reload"
    assert {[$canvas coords "switch-lever:$id:0"] eq $before} "Active-low lever position lost on reload"
    ::svvs::simulation_components::showMenu $id 0 0 0
    .signalBlockMenu.switchRaisedValue invoke 0
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    assert {[dict get $module simulationConfig value] == 11} "Restoring active-high output failed"
}
if {[catch {testSwitch} message options]} {
    puts stderr [dict get $options -errorinfo]
    exit 1
}
puts "Switch UI and simulation tests: ok"
destroy .
exit 0
