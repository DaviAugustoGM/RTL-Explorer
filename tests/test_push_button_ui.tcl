set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "$message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]
proc assert {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc buttonValue {id} {
    return [dict get $::svvs::canvas_blocks::blocks($id) module simulationConfig value]
}
proc pressButton {id bit} {
    set canvas $::svvs::canvas_blocks::canvas
    lassign [$canvas coords "switch-knob:$id:$bit"] x1 y1 x2 y2
    set x [expr {int(($x1 + $x2) / 2 - [$canvas canvasx 0])}]
    set y [expr {int(($y1 + $y2) / 2 - [$canvas canvasy 0])}]
    event generate $canvas <Motion> -x $x -y $y
    event generate $canvas <ButtonPress-1> -x $x -y $y
    update
}
proc testPushButton {} {
    set template [::svvs::simulation_components::templateByKind push_button]
    assert {$template ne ""} "Push button missing"
    set id [::svvs::canvas_blocks::drawBlock $template 250 150]
    set canvas $::svvs::canvas_blocks::canvas
    update
    focus -force $canvas
    update
    set original [$canvas coords "switch-knob:$id:0"]
    pressButton $id 0
    assert {[buttonValue $id] == 1} "Press did not activate button"
    assert {[$canvas coords "switch-knob:$id:0"] ne $original} "Button did not depress visually"
    update
    assert {[buttonValue $id] == 1} "Button did not stay active while held"
    set startX [dict get $::svvs::canvas_blocks::blocks($id) x]
    event generate $canvas <B1-Motion> -x 5 -y 5
    assert {[dict get $::svvs::canvas_blocks::blocks($id) x] == $startX} "Holding button moved its block"
    event generate $canvas <ButtonRelease-1> -x 5 -y 5
    update
    assert {[buttonValue $id] == 0} "Release outside did not reset button"
    assert {[$canvas coords "switch-knob:$id:0"] eq $original} "Button did not return visually"
    pressButton $id 0
    rename focus realFocus
    proc focus {args} { return "" }
    ::svvs::simulation_components::checkPushButtonFocus
    rename focus {}
    rename realFocus focus
    assert {[buttonValue $id] == 0} "Focus loss did not reset button"
    ::svvs::simulation_components::showMenu $id 0 0 0
    assert {[.signalBlockMenu.switchRaisedValue entrycget 1 -label] eq "Enviar 0 ao pressionar"} "Active-low menu missing"
    .signalBlockMenu.switchRaisedValue invoke 1
    assert {[buttonValue $id] == 1} "Active-low idle should be one"
    pressButton $id 0
    assert {[buttonValue $id] == 0} "Active-low press should send zero"
    event generate $canvas <ButtonRelease-1> -x 5 -y 5
    assert {[buttonValue $id] == 1} "Active-low release should send one"
    ::svvs::simulation_components::setPortWidth "port:$id:out" 4
    assert {[buttonValue $id] == 15} "Widened active-low bank should idle high"
    set led [::svvs::canvas_blocks::drawBlock [::svvs::simulation_components::templateByKind led] 500 150]
    ::svvs::canvas_connections::drawConnection "port:$id:out" "port:$led:in"
    assert {[llength [$canvas find withtag "switch-track:$id"]] == 4} "Bank did not create four buttons"
    set model [::svvs::simulation_model::diagramModel]
    assert {[llength [dict get $model errors]] == 0} "Push-button model contains errors"
    ::svvs::diagram_simulation::activate $model
    set signal $::svvs::diagram_simulation::portSignals(port:$id:out)
    pressButton $id 2
    assert {[buttonValue $id] == 11} "Button did not operate independently"
    assert {$::svvs::simulator_view::signalVars($signal) == 11} "Press did not send live value"
    set data [::svvs::canvas_blocks::exportDiagramData]
    set saved [lindex [dict get $data nodes] 0]
    assert {[dict get $saved module simulationConfig value] == 15} "Pressed state should not be persisted"
    event generate $canvas <ButtonRelease-1> -x 5 -y 5
    assert {$::svvs::simulator_view::signalVars($signal) == 15} "Release did not send live idle value"
    ::svvs::diagram_simulation::deactivate
    ::svvs::canvas_blocks::clearCanvas
    ::svvs::canvas_blocks::importDiagramData $data
    assert {[buttonValue $id] == 15} "Reload did not restore idle value"
    assert {[dict get $::svvs::canvas_blocks::blocks($id) module simulationConfig raisedValue] == 0} "Polarity lost on reload"
    set handle [lindex [$canvas find withtag "resize:$id"] 0]
    assert {[$canvas itemcget $handle -state] ne "hidden"} "Button resize handle missing"
    set width [dict get $::svvs::canvas_blocks::blocks($id) width]
    ::svvs::canvas_blocks::resizeBlockBy "resize:$id" 30 20
    assert {[dict get $::svvs::canvas_blocks::blocks($id) width] > $width} "Button could not resize"
}
if {[catch {testPushButton} message options]} {
    puts stderr [dict get $options -errorinfo]
    exit 1
}
puts "Push-button UI and simulation tests: ok"
destroy .
exit 0
