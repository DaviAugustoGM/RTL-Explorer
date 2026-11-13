set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "UI ERROR: $message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]

proc checkWideSignals {} {
    set components [::svvs::project_tree::builtinModules simulation]
    set probe [::svvs::canvas_blocks::drawBlock \
        [::svvs::canvas_blocks::nextInstanceModule [lindex $components 1]] 100 100]
    ::svvs::simulation_components::setPortWidth "port:$probe:in" 128
    ::svvs::simulation_components::setConfig $probe base hex
    ::svvs::canvas_blocks::resizeBlockBy "resize:$probe" 440 40
    set value [expr {0xFEDCBA98765432100123456789ABCDEF}]
    set expected 0xFEDCBA98765432100123456789ABCDEF
    ::svvs::simulation_components::updateDisplay $probe $value
    set canvas $::svvs::canvas_blocks::canvas
    if {[$canvas itemcget "simulation-component:$probe" -text] ne $expected} {
        error "128-bit output probe did not show the complete hexadecimal value"
    }
    foreach literal [list $value $expected "0b[format %llb $value]"] {
        if {[::svvs::diagram_simulation::integerValue $literal] != $value} {
            error "diagram lost upper bits for $literal"
        }
    }
    set input [::svvs::canvas_blocks::drawBlock \
        [::svvs::canvas_blocks::nextInstanceModule [lindex $components 0]] 100 300]
    ::svvs::simulation_components::setPortWidth "port:$input:out" 128
    ::svvs::simulation_components::setConfig $input base hex
    ::svvs::simulation_components::setConfig $input value $value
    ::svvs::simulation_components::editValueDialog $input
    if {$::svvs::simulation_components::editValue ne $expected} {
        error "128-bit input editor lost upper bits"
    }
    puts "wide signal UI tests: ok"
    destroy .
    set ::testDone 1
}
after 300 checkWideSignals
vwait ::testDone
