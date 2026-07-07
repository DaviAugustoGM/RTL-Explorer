set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "UI ERROR: $message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]

proc setupAutoIoTest {} {
    set files [list [file join $::root sample producer.sv]]
    ::svvs::project_tree::loadProjectFiles $files sample
    set producer [lindex $::svvs::project_tree::sampleModules 0]
    set block [::svvs::canvas_blocks::drawBlock $producer 300 180]
    set ::svvs::canvas_blocks::selectedTag "block:$block"

    set created [::svvs::simulation_components::autoIoForSelected both]
    if {$created != 5} {
        error "expected 5 signal blocks for producer, got $created"
    }

    set inputSignals 0
    set outputProbes 0
    set clocks 0
    set labels {}
    foreach id [array names ::svvs::canvas_blocks::blocks] {
        set module [dict get $::svvs::canvas_blocks::blocks($id) module]
        set kind [::svvs::simulation_components::kind $module]
        if {$kind eq "input"} { incr inputSignals }
        if {$kind eq "probe"} { incr outputProbes }
        if {$kind eq "clock"} { incr clocks }
        if {$kind in {input probe clock}} {
            lappend labels [::svvs::simulation_components::config $module label ""]
        }
    }
    if {$inputSignals != 2 || $clocks != 1 || $outputProbes != 2} {
        error "auto I/O created wrong signal block counts: inputs=$inputSignals clocks=$clocks probes=$outputProbes"
    }
    foreach label {clk rst_n enable data valid} {
        if {[lsearch -exact $labels $label] < 0} {
            error "auto I/O did not assign label $label"
        }
    }
    if {[array size ::svvs::canvas_connections::connections] != 5} {
        error "auto I/O did not create five connections"
    }

    set repeated [::svvs::simulation_components::autoIoForSelected both]
    if {$repeated != 0} {
        error "auto I/O created duplicate signal blocks"
    }

    puts "auto I/O UI test: ok"
    destroy .
    set ::testDone 1
}

after 300 setupAutoIoTest
vwait ::testDone
