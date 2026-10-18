set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "$message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]
proc assert {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc testLed {} {
    set template [::svvs::simulation_components::templateByKind led]
    assert {$template ne ""} "LED missing from built-ins"
    set led [::svvs::canvas_blocks::drawBlock $template 300 100]
    set canvas $::svvs::canvas_blocks::canvas
    set item [lindex [$canvas find withtag "simulation-component:$led"] 0]
    assert {[$canvas type $item] eq "oval"} "LED must be circular"
    foreach level {0 1} {
        ::svvs::simulation_components::setConfig $led activeLevel $level
        foreach {color hex} {blue #2196ff red #ff3434 green #35df65 yellow #ffdc32 white #ffffff} {
            ::svvs::simulation_components::setConfig $led ledColor $color
            ::svvs::simulation_components::updateDisplay $led $level
            assert {[$canvas itemcget $item -fill] eq $hex} "LED did not light with $level / $color"
            ::svvs::simulation_components::updateDisplay $led [expr {1 - $level}]
            assert {[$canvas itemcget $item -fill] eq "#30343b"} "LED did not switch off"
            ::svvs::simulation_components::updateDisplay $led x
            assert {[$canvas itemcget $item -fill] eq "#30343b"} "Unknown value lit LED"
        }
    }
    ::svvs::simulation_components::showMenu $led 0 0 0
    assert {[.signalBlockMenu.ledColor index end] == 4} "Five colors expected"
    .signalBlockMenu.ledLevel invoke 0
    .signalBlockMenu.ledColor invoke 0
    set module [dict get $::svvs::canvas_blocks::blocks($led) module]
    assert {[dict get $module simulationConfig activeLevel] == 1} "Menu did not set polarity"
    assert {[dict get $module simulationConfig ledColor] eq "blue"} "Menu did not set color"
    set input [::svvs::canvas_blocks::drawBlock [::svvs::simulation_components::templateByKind input] 80 100]
    ::svvs::canvas_connections::drawConnection "port:$input:out" "port:$led:in" 1
    set model [::svvs::simulation_model::diagramModel]
    set found 0
    foreach signal [dict get $model signalBlocks] {
        if {[dict get $signal block] eq $led} { set found 1 }
    }
    assert {$found} "LED missing from simulated signals"
    ::svvs::diagram_simulation::activate $model
    set signal $::svvs::diagram_simulation::portSignals(port:$led:in)
    ::svvs::diagram_simulation::updateValues [list "$signal=1"]
    assert {[$canvas itemcget $item -fill] eq "#2196ff"} "Simulation did not light LED"
    ::svvs::simulation_components::setConfig $led ledColor green
    assert {[$canvas itemcget $item -fill] eq "#35df65"} "Live color change lost value"
    ::svvs::simulation_components::setConfig $led activeLevel 0
    assert {[$canvas itemcget $item -fill] eq "#30343b"} "Live polarity change did not switch off LED"
    ::svvs::diagram_simulation::updateValues [list "$signal=0"]
    assert {[$canvas itemcget $item -fill] eq "#35df65"} "Active-low LED did not light in simulation"
    ::svvs::canvas_blocks::resizeBlockBy "resize:$led" 20 15
    assert {[llength [$canvas coords $item]] == 4} "LED shape lost during resize"
    ::svvs::diagram_simulation::deactivate
    assert {[$canvas itemcget $item -fill] eq "#30343b"} "Stopped LED stayed lit"
    set data [::svvs::canvas_blocks::exportDiagramData]
    ::svvs::canvas_blocks::importDiagramData $data
    set module [dict get $::svvs::canvas_blocks::blocks($led) module]
    assert {[dict get $module simulationConfig ledColor] eq "green"} "LED color lost on reload"
    assert {[dict get $module simulationConfig activeLevel] == 0} "LED polarity lost on reload"
    # A virtual source must keep its bus width when connected to a fresh LED.
    set bus [::svvs::simulation_components::templateByKind input]
    dict set bus ports [list [dict create name out direction output width 8]]
    dict set bus simulationConfig bitWidth 8
    dict set bus instance bus
    set source [::svvs::canvas_blocks::drawBlock $bus 80 250]
    set bank [::svvs::canvas_blocks::drawBlock $template 300 250]
    set conn [::svvs::canvas_connections::drawConnection "port:$source:out" "port:$bank:in"]
    assert {[::svvs::canvas_connections::portWidth "port:$source:out"] == 8} "LED resized the source bus"
    assert {[::svvs::canvas_connections::portWidth "port:$bank:in"] == 8} "LED did not adopt bus width"
    assert {[llength [$canvas find withtag "simulation-component:$bank"]] == 8} "Expected eight LEDs"
    ::svvs::simulation_components::updateDisplay $bank 165
    for {set bit 0} {$bit < 8} {incr bit} {
        set expected [expr {(165 >> $bit) & 1 ? "#ff3434" : "#30343b"}]
        assert {[$canvas itemcget "led-bit:$bank:$bit" -fill] eq $expected} "Wrong bus bit $bit"
        if {$bit > 0} {
            assert {[lindex [$canvas coords "led-bit:$bank:$bit"] 0] < [lindex [$canvas coords "led-bit:$bank:[expr {$bit - 1}]"] 0]} "Bits are not ordered MSB to LSB"
        }
    }
    # Exercise the same range-editor flow used by the context menu.
    set hardware [dict create name bus_source instance bus_source ports [list [dict create name out direction output width 8]]]
    set driver [::svvs::canvas_blocks::drawBlock $hardware 80 400]
    set ranged [::svvs::canvas_blocks::drawBlock $template 300 400]
    set rangeConn [::svvs::canvas_connections::drawConnection "port:$driver:out" "port:$ranged:in"]
    set ::svvs::canvas_connections::rangeEditConn $rangeConn
    set ::svvs::canvas_connections::rangeEditFrom 6:4
    set ::svvs::canvas_connections::rangeEditTo ""
    ::svvs::canvas_connections::commitRangeDialog
    assert {[::svvs::canvas_connections::portWidth "port:$ranged:in"] == 3} "Range did not resize LED bank"
    assert {[llength [$canvas find withtag "simulation-component:$ranged"]] == 3} "Range did not create three LEDs"
    set model [::svvs::simulation_model::diagramModel]
    assert {[llength [dict get $model errors]] == 0} "Range model contains errors"
    ::svvs::diagram_simulation::activate $model
    set signal $::svvs::diagram_simulation::portSignals(port:$ranged:in)
    ::svvs::diagram_simulation::updateValues [list "$signal=5"]
    assert {[$canvas itemcget "led-bit:$ranged:0" -fill] eq "#ff3434"} "Range bit 0 is wrong"
    assert {[$canvas itemcget "led-bit:$ranged:1" -fill] eq "#30343b"} "Range bit 1 is wrong"
    assert {[$canvas itemcget "led-bit:$ranged:2" -fill] eq "#ff3434"} "Range bit 2 is wrong"
    ::svvs::diagram_simulation::deactivate
    # Verify that synthesis and a real backend deliver the selected bus slice.
    set fixtureDir [file join $::root .rtl_explorer_build led_test]
    file mkdir $fixtureDir
    set fixture [file join $fixtureDir bus_source.sv]
    set handle [open $fixture w]
    puts $handle {module bus_source(output logic [7:0] out); assign out = 8'hA5; endmodule}
    close $handle
    set ::svvs::project_tree::projectFiles [list $fixture]
    set result [::svvs::simulation_model::prepare]
    assert {[dict get $result ok]} "LED bus synthesis failed"
    foreach engine {CXXRTL Icarus} {
        set ::svvs::simulation_backends::selectedEngine $engine
        set backend [::svvs::simulation_backends::prepare $result]
        assert {[dict get $backend ok]} "$engine LED backend failed"
        set channel [open [linsert [dict get $backend command] 0 |] r+]
        fconfigure $channel -buffering line -encoding utf-8
        gets $channel ready
        gets $channel values
        puts $channel QUIT
        flush $channel
        catch {close $channel}
        assert {[string match "READY*" $ready]} "$engine LED backend did not start"
        assert {"$signal=2" in [split $values \t]} "$engine did not simulate the selected slice (6:4 of A5)"
    }
    set data [::svvs::canvas_blocks::exportDiagramData]
    ::svvs::canvas_blocks::importDiagramData $data
    assert {[llength [$canvas find withtag "simulation-component:$ranged"]] == 3} "Range bank lost on reload"
    update
}
if {[catch {testLed} message options]} {
    puts stderr [dict get $options -errorinfo]
    exit 1
}
puts "LED UI and simulation tests: ok"
destroy .
exit 0
