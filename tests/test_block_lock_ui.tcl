set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "$message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]
proc assert {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc testLock {} {
    set id [::svvs::canvas_blocks::drawBlock [::svvs::simulation_components::templateByKind switch] 200 150]
    set before $::svvs::canvas_blocks::blocks($id)
    set canvas $::svvs::canvas_blocks::canvas
    update
    set toolbar $::svvs::layout::widgets(toolbar:Lock\ blocks)
    event generate $toolbar <Button-1>
    assert {$::svvs::canvas_blocks::movementLocked} "Toolbar did not lock blocks"
    assert {$::svvs::layout::toolbarActive($toolbar)} "Lock indicator is inactive"
    ::svvs::canvas_blocks::moveSelectedBlocks "block:$id" 100 50
    ::svvs::canvas_blocks::resizeBlockBy "resize:$id" 80 40
    assert {$::svvs::canvas_blocks::blocks($id) eq $before} "Locked block moved or resized"
    # Selection is still available and does not arm a drag.
    set x [expr {int(202 - [$canvas canvasx 0])}]
    set y [expr {int(152 - [$canvas canvasy 0])}]
    ::svvs::canvas_blocks::onPress $x $y
    ::svvs::canvas_blocks::onDrag [expr {$x + 80}] [expr {$y + 50}]
    ::svvs::canvas_blocks::onRelease [expr {$x + 80}] [expr {$y + 50}]
    assert {$::svvs::canvas_blocks::blocks($id) eq $before} "Pointer drag moved a locked block"
    lassign [$canvas coords "switch-knob:$id:0"] x1 y1 x2 y2
    set x [expr {int(($x1 + $x2) / 2 - [$canvas canvasx 0])}]
    set y [expr {int(($y1 + $y2) / 2 - [$canvas canvasy 0])}]
    event generate $canvas <Motion> -x $x -y $y
    event generate $canvas <ButtonPress-1> -x $x -y $y
    event generate $canvas <ButtonRelease-1> -x $x -y $y
    assert {[dict get $::svvs::canvas_blocks::blocks($id) module simulationConfig value] == 1} "Lock blocked switch interaction"
    event generate $toolbar <Button-1>
    assert {!$::svvs::canvas_blocks::movementLocked} "Toolbar did not unlock blocks"
    ::svvs::canvas_blocks::moveSelectedBlocks "block:$id" 100 50
    assert {[dict get $::svvs::canvas_blocks::blocks($id) x] == 300} "Unlocked block could not move"
    ::svvs::canvas_blocks::resizeBlockBy "resize:$id" 80 40
    assert {[dict get $::svvs::canvas_blocks::blocks($id) width] > [dict get $before width]} "Unlocked block could not resize"
}
if {[catch {testLock} message options]} {
    puts stderr [dict get $options -errorinfo]
    exit 1
}
puts "Block movement lock regression: ok"
destroy .
exit 0
