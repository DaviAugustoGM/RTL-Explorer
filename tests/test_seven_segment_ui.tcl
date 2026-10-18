set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "$message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]
proc assert {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc checkSegments {id value level} {
    set canvas $::svvs::canvas_blocks::canvas
    for {set bit 0} {$bit < 7} {incr bit} {
        set on [expr {($value >> $bit & 1) == $level}]
        set expected [expr {$on ? "normal" : "hidden"}]
        assert {[$canvas itemcget "seven-segment:$id:$bit" -state] eq $expected} "Segment $bit has wrong visibility"
        if {$on} {
            assert {[$canvas itemcget "seven-segment:$id:$bit" -fill] eq "#ff3434"} "Lit segment is not red"
        }
    }
}
proc testDisplay {} {
    set template [::svvs::simulation_components::templateByKind seven_segment]
    assert {$template ne ""} "Display missing from built-ins"
    set id [::svvs::canvas_blocks::drawBlock $template 350 100]
    set canvas $::svvs::canvas_blocks::canvas
    assert {[llength [$canvas find withtag "seven-segment:$id"]] == 7} "Expected seven segments"
    set width [dict get $::svvs::canvas_blocks::blocks($id) width]
    set height [dict get $::svvs::canvas_blocks::blocks($id) height]
    ::svvs::simulation_components::setPortWidth "port:$id:segments" 16
    set original [$canvas coords "seven-segment:$id:0"]
    ::svvs::canvas_blocks::resizeBlockBy "resize:$id" 100 100
    assert {[::svvs::canvas_connections::portWidth "port:$id:segments"] == 7} "Display input did not stay at seven bits"
    assert {[dict get $::svvs::canvas_blocks::blocks($id) width] > $width} "Display did not grow"
    set ratio [expr {$width / double($height)}]
    assert {abs([dict get $::svvs::canvas_blocks::blocks($id) width] /
        [dict get $::svvs::canvas_blocks::blocks($id) height] - $ratio) < 0.00001} "Display lost aspect ratio"
    assert {[$canvas coords "seven-segment:$id:0"] ne $original} "Segments did not scale with display"
    ::svvs::canvas_blocks::resizeBlockBy "resize:$id" -100 -100
    assert {abs([dict get $::svvs::canvas_blocks::blocks($id) width] - $width) < 0.00001} "Display did not shrink"
    assert {abs([dict get $::svvs::canvas_blocks::blocks($id) height] - $height) < 0.00001} "Display height did not return"
    foreach movement {{70 0} {-70 0} {0 70} {0 -70} {-10000 -10000} {100 30}} {
        ::svvs::canvas_blocks::resizeBlockBy "resize:$id" {*}$movement
        assert {abs([dict get $::svvs::canvas_blocks::blocks($id) width] /
            [dict get $::svvs::canvas_blocks::blocks($id) height] - $ratio) < 0.00001} "One-axis resize distorted display"
    }
    set width [dict get $::svvs::canvas_blocks::blocks($id) width]
    set handle [lindex [$canvas find withtag "resize:$id"] 0]
    assert {[$canvas itemcget $handle -state] ne "hidden"} "Display resize handle should be visible"
    foreach level {0 1} {
        ::svvs::simulation_components::setConfig $id activeLevel $level
        foreach value {0 127 63 6 91 79 102 109 125 7 111 1 2 4 8 16 32 64} {
            ::svvs::simulation_components::updateDisplay $id $value
            checkSegments $id $value $level
        }
        ::svvs::simulation_components::updateDisplay $id x
        foreach item [$canvas find withtag "seven-segment:$id"] {
            assert {[$canvas itemcget $item -state] eq "hidden"} "Unknown signal showed a segment"
        }
    }
    ::svvs::simulation_components::showMenu $id 0 0 0
    assert {[.signalBlockMenu.displayLevel index end] == 1} "Polarity options missing"
    .signalBlockMenu.displayLevel invoke 0
    set source [::svvs::canvas_blocks::drawBlock [::svvs::simulation_components::templateByKind switch] 100 100]
    ::svvs::canvas_connections::drawConnection "port:$source:out" "port:$id:segments"
    assert {[::svvs::canvas_connections::portWidth "port:$source:out"] == 7} "Source did not adapt to display"
    assert {[dict get $::svvs::canvas_blocks::blocks($id) width] == $width} "Connection changed display size"
    set model [::svvs::simulation_model::diagramModel]
    assert {[llength [dict get $model errors]] == 0} "Display model contains errors"
    ::svvs::diagram_simulation::activate $model
    set signal $::svvs::diagram_simulation::portSignals(port:$id:segments)
    ::svvs::diagram_simulation::updateValues [list "$signal=63"]
    checkSegments $id 63 1
    ::svvs::simulation_components::showMenu $id 0 0 0
    .signalBlockMenu.displayLevel invoke 1
    checkSegments $id 63 0
    ::svvs::diagram_simulation::deactivate
    foreach item [$canvas find withtag "seven-segment:$id"] {
        assert {[$canvas itemcget $item -state] eq "hidden"} "Stopped display showed a segment"
    }
    set data [::svvs::canvas_blocks::exportDiagramData]
    ::svvs::canvas_blocks::clearCanvas
    ::svvs::canvas_blocks::importDiagramData $data
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    assert {[dict get $module simulationConfig activeLevel] == 0} "Display polarity lost on reload"
    assert {[llength [$canvas find withtag "seven-segment:$id"]] == 7} "Display lost on reload"
    update
}
if {[catch {testDisplay} message options]} {
    puts stderr [dict get $options -errorinfo]
    exit 1
}
puts "Seven-segment UI and simulation tests: ok"
destroy .
exit 0
