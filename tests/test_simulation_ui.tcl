package require Tk

set root [file dirname [file dirname [file normalize [info script]]]]
cd $root

proc bgerror {message} {
    puts stderr "UI ERROR: $message"
    exit 1
}

source [file join $root src main.tcl]

proc setupSimulationTest {} {
    set ::backendPrepareCalls 0
    rename ::svvs::simulation_backends::prepare ::svvs::simulation_backends::realPrepare
    proc ::svvs::simulation_backends::prepare {result} {
        incr ::backendPrepareCalls
        return [::svvs::simulation_backends::realPrepare $result]
    }
    set files [list [file join $::root sample producer.sv] [file join $::root sample consumer.sv]]
    ::svvs::project_tree::loadProjectFiles $files sample
    set modules $::svvs::project_tree::sampleModules
    set ::svvs::project_tree::fsms [list \
        [dict create module control_unit stateVariable current_state]]
    set producer [lindex $modules 0]
    set consumer [lindex $modules 1]
    set p [::svvs::canvas_blocks::drawBlock $producer 80 80]
    set c [::svvs::canvas_blocks::drawBlock $consumer 420 80]
    foreach pair [list \
            [list clk clk] [list rst_n rst_n] [list data data] [list valid valid]] {
        lassign $pair from to
        ::svvs::canvas_connections::drawConnection "port:$p:$from" "port:$c:$to"
    }
    $::svvs::layout::widgets(notebook) select $::svvs::layout::widgets(simTab)
    ::svvs::simulator_view::refreshSignals
    ::svvs::simulator_view::buildAndRun
    after 700 finishSimulationTest
}

proc finishSimulationTest {} {
    if {$::svvs::simulator_view::process eq ""} { error "backend process stopped" }
    if {!$::svvs::simulator_view::running} { error "Build and Run did not start simulation" }
    if {!$::svvs::diagram_simulation::active} { error "diagram simulation is not active" }
    if {[llength [array names ::svvs::simulator_view::fsmWatches]] != 0} {
        error "an FSM outside the diagram was sent to the simulation backend"
    }
    set canvas $::svvs::canvas_blocks::canvas
    if {[llength [$canvas find withtag simulation-overlay]] == 0} {
        error "simulation values were not drawn on the diagram"
    }
    if {[$::svvs::layout::widgets(notebook) select] ne $::svvs::layout::widgets(canvasTab)} {
        error "simulation did not return to the diagram"
    }
    set controls [winfo parent $::svvs::simulator_view::pauseButton]
    set labels {}
    foreach widget [winfo children $controls] {
        if {![catch {$widget cget -text} text]} { lappend labels $text }
    }
    foreach expected {Run {Build and Run} Pause Stop} {
        if {$expected ni $labels} { error "missing simulation control: $expected" }
    }
    foreach removed {Build Step} {
        if {$removed in $labels} { error "obsolete simulation control remains: $removed" }
    }
    if {[winfo ismapped $::svvs::simulator_view::inputPanel] ||
            [winfo ismapped $::svvs::simulator_view::outputPanel]} {
        error "Simulation tab still displays generic input/output controls"
    }
    foreach expected {Run {Build and Run} Pause Stop} {
        if {![info exists ::svvs::layout::widgets(toolbar:$expected)]} {
            error "missing top toolbar control: $expected"
        }
    }
    foreach removed {Reset Step} {
        if {[info exists ::svvs::layout::widgets(toolbar:$removed)]} {
            error "obsolete top toolbar control remains: $removed"
        }
    }
    ::svvs::simulator_view::pause
    if {$::svvs::simulator_view::running ||
            [$::svvs::simulator_view::pauseButton cget -text] ne "Continue"} {
        error "Pause did not change to Continue"
    }
    if {[$::svvs::layout::widgets(toolbar:Pause) cget -text] ne "Continue"} {
        error "top toolbar Pause did not change to Continue"
    }
    ::svvs::simulator_view::pause
    if {!$::svvs::simulator_view::running ||
            [$::svvs::simulator_view::pauseButton cget -text] ne "Pause"} {
        error "Continue did not resume simulation"
    }
    ::svvs::simulator_view::stop
    if {$::svvs::simulator_view::process ne "" ||
            $::svvs::simulator_view::lastBuildResult eq ""} {
        error "Stop did not preserve the previous build"
    }
    ::svvs::simulator_view::pause
    if {$::svvs::simulator_view::process ne ""} {
        error "Pause restarted a stopped simulation"
    }
    set cachedBackend $::svvs::simulator_view::lastBackend
    ::svvs::simulator_view::run
    if {$::svvs::simulator_view::process eq "" ||
            $::svvs::simulator_view::lastBackend ne $cachedBackend} {
        error "Run did not reuse the previous backend"
    }
    if {$::backendPrepareCalls != 1} {
        error "Run rebuilt the backend instead of reusing it"
    }
    puts "simulation UI test: ok"
    ::svvs::simulator_view::closeProcess
    destroy .
    set ::testDone 1
}

after 300 setupSimulationTest
vwait ::testDone
