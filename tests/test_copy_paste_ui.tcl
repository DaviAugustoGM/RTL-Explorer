set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "$message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]
proc assert {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc testCopyPaste {} {
    set c $::svvs::canvas_blocks::canvas
    update
    focus -force $c
    set module [::svvs::simulation_components::templateByKind switch]
    dict set module simulationConfig bitWidth 4
    dict set module simulationConfig value 5
    dict set module instance original
    set a [::svvs::canvas_blocks::drawBlockWithId block900 $module 100 120 240 180]
    set b [::svvs::canvas_blocks::drawBlockWithId block901 $module 400 220 280 200]
    ::svvs::canvas_blocks::updateBlockSeq
    set ::svvs::canvas_blocks::selectedTags [list block:$a block:$b]
    set ::svvs::canvas_blocks::selectedTag block:$a
    event generate $c <Control-c>
    assert {[llength $::svvs::canvas_blocks::copiedNodes] == 2} "Ctrl+C did not copy selection"
    # Copies are snapshots; later edits to the source must not affect them.
    dict set ::svvs::canvas_blocks::blocks($a) module simulationConfig value 0
    ::svvs::canvas_blocks::onWheel 1 100 100
    event generate $c <Control-v>
    set tags $::svvs::canvas_blocks::selectedTags
    assert {[llength $tags] == 2} "Ctrl+V did not paste selection"
    set pasted {}
    foreach tag $tags {
        set id [::svvs::canvas_blocks::blockIdFromTag $tag]
        lappend pasted $::svvs::canvas_blocks::blocks($id)
    }
    set first [lindex $pasted 0]
    set second [lindex $pasted 1]
    set z $::svvs::canvas_blocks::zoom
    assert {abs([dict get $first width] - 240*$z) < 0.001} "Copied width changed"
    assert {abs([dict get $first height] - 180*$z) < 0.001} "Copied height changed"
    assert {abs([dict get $second x] - [dict get $first x] - 300*$z) < 0.001} "Group spacing changed"
    assert {[dict get $first module simulationConfig value] == 5} "Copied configuration changed"
    assert {[dict get $first module simulationConfig bitWidth] == 4} "Copied bit width changed"
    assert {[dict get $first module instance] ne [dict get $second module instance]} "Instances are not unique"
    event generate $c <<Paste>>
    assert {[llength $::svvs::canvas_blocks::selectedTags] == 2} "Virtual paste failed"
    set ::svvs::canvas_blocks::selectedTags {}
    set ::svvs::canvas_blocks::selectedTag block:$a
    event generate $c <<Copy>>
    assert {[llength $::svvs::canvas_blocks::copiedNodes] == 1} "Single-block copy failed"

    # Real pointer selection must retain keyboard focus on the diagram.
    set led [::svvs::simulation_components::templateByKind led]
    dict set led instance original_led
    set id [::svvs::canvas_blocks::drawBlock $led 650 400]
    set original $::svvs::canvas_blocks::blocks($id)
    set x [expr {int(670 - [$c canvasx 0])}]
    set y [expr {int(420 - [$c canvasy 0])}]
    event generate $c <Motion> -x $x -y $y
    event generate $c <ButtonPress-1> -x $x -y $y
    event generate $c <ButtonRelease-1> -x $x -y $y
    assert {[focus] eq $c} "Click moved keyboard focus away from diagram"
    assert {$::svvs::canvas_blocks::selectedTag eq "block:$id"} "LED click did not select LED"
    event generate [focus] <Control-c>
    event generate [focus] <Control-v>
    set copyId [::svvs::canvas_blocks::selectedBlockId]
    assert {$copyId ne $id} "LED was not pasted after clicking"
    set copy $::svvs::canvas_blocks::blocks($copyId)
    foreach key {x y width height} {
        assert {abs([dict get $copy $key] - [dict get $original $key]) < 0.001} "LED position or dimension changed"
    }
    assert {[dict get $copy module simulationConfig] eq [dict get $original module simulationConfig]} "LED settings changed"
}
if {[catch {testCopyPaste} message options]} {
    puts stderr [dict get $options -errorinfo]
    exit 1
}
puts "Copy/paste regression: ok"
destroy .
exit 0
