package require Tk

set root [file dirname [file dirname [file normalize [info script]]]]
cd $root

proc bgerror {message} {
    puts stderr "UI ERROR: $message"
    exit 1
}

source [file join $root src main.tcl]
update idletasks

set diagram $::svvs::canvas_blocks::canvas
set fsm $::svvs::fsm_viewer::canvas
set waveform $::svvs::simulator_view::waveform

foreach widget [list $diagram $fsm $waveform] {
    foreach event {<MouseWheel> <Button-4> <Button-5>} {
        if {[bind $widget $event] eq ""} {
            error "missing cross-platform wheel binding $event on $widget"
        }
    }
}

foreach widget [list $diagram $fsm] {
    foreach event {<Control-plus> <Control-minus> <Control-Key-0> <Left> <Right> <Up> <Down>} {
        if {[bind $widget $event] eq ""} {
            error "missing keyboard navigation binding $event on $widget"
        }
    }
    foreach event {<Shift-ButtonPress-1> <Shift-B1-Motion> <Shift-ButtonRelease-1>} {
        if {[bind $widget $event] eq ""} {
            error "missing keyboard-assisted pan binding $event on $widget"
        }
    }
}

set ::svvs::canvas_blocks::zoom 1.0
::svvs::canvas_blocks::onWheel 120 100 100
if {$::svvs::canvas_blocks::zoom <= 1.0} { error "Windows wheel delta did not zoom in" }
::svvs::canvas_blocks::resetView
if {$::svvs::canvas_blocks::zoom != 1.0} { error "diagram reset zoom failed" }

set ::svvs::fsm_viewer::zoom 1.0
::svvs::fsm_viewer::onWheel 1 100 100
if {$::svvs::fsm_viewer::zoom <= 1.0} { error "Linux wheel event did not zoom FSM in" }
::svvs::fsm_viewer::resetView

puts "cross-platform input bindings test: ok"
destroy .
