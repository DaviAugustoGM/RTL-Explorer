set root [file dirname [file dirname [file normalize [info script]]]]
cd $root

proc bgerror {message} {
    puts stderr "UI ERROR: $message"
    exit 1
}

source [file join $root src main.tcl]

proc setupSimulationTest {} {
    set files [list [file join $::root sample producer.sv] [file join $::root sample consumer.sv]]
    ::svvs::project_tree::loadProjectFiles $files sample
    set modules $::svvs::project_tree::sampleModules
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
    if {![::svvs::simulator_view::build]} { error "simulation build failed" }
    ::svvs::simulator_view::step
    after 700 finishSimulationTest
}

proc finishSimulationTest {} {
    if {$::svvs::simulator_view::process eq ""} { error "backend process stopped" }
    if {!$::svvs::diagram_simulation::active} { error "diagram simulation is not active" }
    set canvas $::svvs::canvas_blocks::canvas
    if {[llength [$canvas find withtag simulation-overlay]] == 0} {
        error "simulation values were not drawn on the diagram"
    }
    if {[$::svvs::layout::widgets(notebook) select] ne $::svvs::layout::widgets(canvasTab)} {
        error "simulation did not return to the diagram"
    }
    puts "simulation UI test: ok"
    ::svvs::simulator_view::closeProcess
    destroy .
    set ::testDone 1
}

after 300 setupSimulationTest
vwait ::testDone
