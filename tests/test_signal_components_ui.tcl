set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "UI ERROR: $message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]

proc setupSignalComponentTest {} {
    set files [list [file join $::root sample producer.sv]]
    ::svvs::project_tree::loadProjectFiles $files sample
    set producer [lindex $::svvs::project_tree::sampleModules 0]
    set p [::svvs::canvas_blocks::drawBlock $producer 350 100]
    set components [::svvs::project_tree::builtinModules simulation]
    set inputTemplate [lindex $components 0]
    set probeTemplate [lindex $components 1]
    set clockTemplate [lindex $components 2]

    set enable [::svvs::canvas_blocks::drawBlock \
        [::svvs::canvas_blocks::nextInstanceModule $inputTemplate] 80 80]
    set ::testInputBlock $enable
    if {[dict get $::svvs::canvas_blocks::blocks($enable) width] != 64 ||
        [dict get $::svvs::canvas_blocks::blocks($enable) height] != 64} {
        error "built-in signal block is not compact"
    }
    set inputHandle [lindex [$::svvs::canvas_blocks::canvas find withtag "resize:$enable"] 0]
    if {$inputHandle eq "" ||
        [$::svvs::canvas_blocks::canvas itemcget $inputHandle -state] eq "hidden"} {
        error "input signal resize handle is not visible"
    }
    ::svvs::canvas_blocks::resizeBlockBy "resize:$enable" 56 30
    if {[dict get $::svvs::canvas_blocks::blocks($enable) width] != 120 ||
        [dict get $::svvs::canvas_blocks::blocks($enable) height] != 94} {
        error "input signal could not be resized"
    }
    foreach item [$::svvs::canvas_blocks::canvas find withtag "block:$enable"] {
        set tags [$::svvs::canvas_blocks::canvas gettags $item]
        if {[lsearch -exact $tags simulation-hidden] >= 0 &&
            [$::svvs::canvas_blocks::canvas itemcget $item -state] ne "hidden"} {
            error "compact block decoration is visible"
        }
    }
    ::svvs::simulation_components::activateBlock $enable
    set enableModule [dict get $::svvs::canvas_blocks::blocks($enable) module]
    if {[dict get $enableModule simulationConfig value] != 1} {
        error "one-bit input did not toggle automatically"
    }
    ::svvs::simulation_components::showMenu $enable 20 20 0
    if {![winfo exists .signalBlockMenu] || [.signalBlockMenu entrycget 0 -label] ne "Rename..."} {
        error "signal block context menu was not created"
    }
    set resetModule [::svvs::canvas_blocks::nextInstanceModule $inputTemplate]
    dict set resetModule simulationConfig value 1
    set reset [::svvs::canvas_blocks::drawBlock $resetModule 80 210]
    set clock [::svvs::canvas_blocks::drawBlock \
        [::svvs::canvas_blocks::nextInstanceModule $clockTemplate] 80 340]
    set probe [::svvs::canvas_blocks::drawBlock \
        [::svvs::canvas_blocks::nextInstanceModule $probeTemplate] 700 100]
    set probeHandle [lindex [$::svvs::canvas_blocks::canvas find withtag "resize:$probe"] 0]
    if {$probeHandle eq "" ||
        [$::svvs::canvas_blocks::canvas itemcget $probeHandle -state] eq "hidden"} {
        error "output probe resize handle is not visible"
    }
    ::svvs::canvas_blocks::resizeBlockBy "resize:$probe" 76 40
    if {[dict get $::svvs::canvas_blocks::blocks($probe) width] != 140 ||
        [dict get $::svvs::canvas_blocks::blocks($probe) height] != 104} {
        error "output probe could not be resized"
    }
    set counter [::svvs::canvas_blocks::drawBlock \
        [::svvs::canvas_blocks::nextInstanceModule $inputTemplate] 80 470]
    ::svvs::simulation_components::setPortWidth "port:$counter:out" 8
    ::svvs::simulation_components::setClickAction $counter increment
    ::svvs::simulation_components::setConfig $counter value 255
    ::svvs::simulation_components::activateBlock $counter
    set counterModule [dict get $::svvs::canvas_blocks::blocks($counter) module]
    if {[dict get $counterModule simulationConfig value] != 0} {
        error "incrementing input did not wrap to zero"
    }

    ::svvs::canvas_connections::drawConnection "port:$enable:out" "port:$p:enable"
    ::svvs::canvas_connections::drawConnection "port:$reset:out" "port:$p:rst_n"
    ::svvs::canvas_connections::drawConnection "port:$clock:clk" "port:$p:clk"
    ::svvs::canvas_connections::drawConnection "port:$p:data" "port:$probe:in"
    ::svvs::simulation_components::setConfig $probe valueMap [dict create 3 READY]
    ::svvs::simulation_components::showMenu $probe 20 20 0
    set hasValueLabels 0
    for {set menuIndex 0} {$menuIndex <= [.signalBlockMenu index end]} {incr menuIndex} {
        if {[.signalBlockMenu type $menuIndex] ne "separator" &&
            [.signalBlockMenu entrycget $menuIndex -label] eq "Value labels..."} {
            set hasValueLabels 1
        }
    }
    if {!$hasValueLabels} { error "probe value-label editor is missing from its menu" }
    ::svvs::simulation_components::valueMapDialog $probe
    set ::svvs::simulation_components::mapValue 0x4
    set ::svvs::simulation_components::mapText BUSY
    ::svvs::simulation_components::commitValueMapEntry
    destroy .valueMapEditor

    set enableModule [dict get $::svvs::canvas_blocks::blocks($enable) module]
    if {[dict get $enableModule simulationConfig label] ne "enable"} {
        error "input did not receive the first connected port name"
    }
    set probeModule [dict get $::svvs::canvas_blocks::blocks($probe) module]
    if {[dict get $probeModule simulationConfig label] ne "data"} {
        error "probe did not receive the connected output name"
    }
    if {[::svvs::simulation_components::formatMappedValue 3 8 hex \
        [dict get $probeModule simulationConfig valueMap]] ne "READY"} {
        error "probe value label was not retained"
    }
    if {[::svvs::simulation_components::formatMappedValue 4 8 hex \
        [dict get $probeModule simulationConfig valueMap]] ne "BUSY"} {
        error "probe value-label editor did not save a hexadecimal mapping"
    }
    ::svvs::simulation_components::setConfig $probe label data_bus
    ::svvs::simulation_components::setConfig $probe nameAssigned 1

    set probePort $::svvs::canvas_blocks::tagToPort(port:$probe:in)
    if {[dict get $probePort width] != 8} { error "probe did not adapt to 8 bits" }
    set model [::svvs::simulation_model::diagramModel]
    if {[llength [dict get $model clocks]] != 1} { error "clock metadata missing" }
    set ::testClockName [dict get [lindex [dict get $model clocks] 0] name]
    if {[llength [dict get $model traces]] < 4} { error "waveform traces missing" }
    set traceLabels {}
    foreach trace [dict get $model traces] { lappend traceLabels [dict get $trace label] }
    if {[lsearch -exact $traceLabels data_bus] < 0} { error "renamed signal is missing from waveform" }
    set mappedTrace 0
    foreach trace [dict get $model traces] {
        if {[dict exists $trace valueMap] && [dict exists [dict get $trace valueMap] 3] &&
            [dict get [dict get $trace valueMap] 3] eq "READY"} { set mappedTrace 1 }
    }
    if {!$mappedTrace} { error "probe value labels are missing from the waveform model" }
    set savedProbeSize 0
    foreach node [dict get [::svvs::canvas_blocks::exportDiagramData] nodes] {
        if {[dict get $node id] eq $probe && [dict get $node width] == 140 &&
            [dict get $node height] == 104} { set savedProbeSize 1 }
    }
    if {!$savedProbeSize} { error "resized output probe dimensions were not exported" }
    set ::svvs::demo_scenarios::scenarios [list [dict create name Regression steps [list \
        [dict create duration 250 values [dict create test_signal 1]]]]]
    set ::svvs::demo_scenarios::selected Regression
    set savedDemos [::svvs::demo_scenarios::exportData]
    ::svvs::demo_scenarios::reset
    ::svvs::demo_scenarios::importData $savedDemos
    if {[llength $::svvs::demo_scenarios::scenarios] != 1} {
        error "demo scenarios were not restored"
    }
    if {[::svvs::demo_scenarios::stepTriggerLabel \
        [dict create duration 250 values {}]] ne "250 ms"} {
        error "legacy timed scenario label is invalid"
    }
    if {[::svvs::demo_scenarios::stepTriggerLabel \
        [dict create trigger rising clock $::testClockName values {}]] ne \
        "Rising: $::testClockName"} {
        error "rising-edge scenario label is invalid"
    }
    set ::svvs::demo_scenarios::waitingClock $::testClockName
    set ::svvs::demo_scenarios::waitingEdge rising
    set ::svvs::demo_scenarios::remainingEdges 2
    ::svvs::demo_scenarios::clockEdge $::testClockName falling
    ::svvs::demo_scenarios::clockEdge another_clock rising
    if {$::svvs::demo_scenarios::remainingEdges != 2} {
        error "scenario accepted an unrelated clock edge"
    }
    ::svvs::demo_scenarios::clockEdge $::testClockName rising
    if {$::svvs::demo_scenarios::remainingEdges != 1} {
        error "scenario cycle counter did not consume a rising edge"
    }
    ::svvs::demo_scenarios::stop
    if {![::svvs::simulator_view::build]} { error "component simulation build failed" }
    ::svvs::simulator_view::run
    after 350 changeInputWithoutClockEdge
    after 950 finishSignalComponentTest
}

proc changeInputWithoutClockEdge {} {
    set name $::testClockName
    if {![info exists ::svvs::simulator_view::clockStates($name)]} {
        error "clock scheduler state unavailable"
    }
    set ::clockBeforeInputChange $::svvs::simulator_view::clockStates($name)
    set ::clockSamplesBeforeInputChange [llength $::svvs::simulator_view::history($name)]
    ::svvs::simulation_components::activateBlock $::testInputBlock
    after 80 verifyClockPhaseWasPreserved
}

proc verifyClockPhaseWasPreserved {} {
    set current $::svvs::simulator_view::clockStates($::testClockName)
    if {$current ne $::clockBeforeInputChange} {
        error "editing an input changed the clock phase"
    }
    if {[llength $::svvs::simulator_view::history($::testClockName)] !=
        $::clockSamplesBeforeInputChange} {
        error "input event stretched the clock waveform"
    }
}

proc finishSignalComponentTest {} {
    if {$::svvs::simulator_view::process eq ""} { error "backend stopped" }
    if {!$::svvs::diagram_simulation::active} { error "diagram simulation inactive" }
    if {![winfo exists $::svvs::simulator_view::waveform] ||
        [winfo parent $::svvs::simulator_view::waveform] ne ".main.vertical.waveforms"} {
        error "waveform panel is not between workspace and console"
    }
    set busShapes 0
    foreach item [$::svvs::simulator_view::waveform find all] {
        if {[$::svvs::simulator_view::waveform type $item] eq "polygon"} { incr busShapes }
    }
    if {$busShapes == 0} { error "multi-bit waveform was not drawn as a bus" }
    set scrollregion [$::svvs::simulator_view::waveform cget -scrollregion]
    if {[lindex $scrollregion 3] <= [winfo height $::svvs::simulator_view::waveform]} {
        error "waveform panel did not create a responsive scroll region"
    }
    if {![info exists ::svvs::simulator_view::history($::testClockName)] ||
        [llength $::svvs::simulator_view::history($::testClockName)] < 2} {
        error "clock waveform was not sampled in real time"
    }
    puts "signal component UI test: ok"
    ::svvs::simulator_view::closeProcess
    destroy .
    set ::testDone 1
}

after 300 setupSignalComponentTest
vwait ::testDone
