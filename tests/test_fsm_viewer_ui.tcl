set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "UI ERROR: $message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]

proc sequentialFsm {module states} {
    set transitions {}
    for {set i 0} {$i + 1 < [llength $states]} {incr i} {
        lappend transitions [dict create from [lindex $states $i] \
            to [lindex $states [expr {$i + 1}]] condition default]
    }
    return [dict create name "${module}_state" module $module stateVariable state \
        states $states transitions $transitions]
}

proc rectanglesOverlap {a b} {
    lassign $a ax1 ay1 ax2 ay2
    lassign $b bx1 by1 bx2 by2
    return [expr {$ax1 < $bx2 && $ax2 > $bx1 && $ay1 < $by2 && $ay2 > $by1}]
}

proc runFsmViewerTest {} {
    set alphaPath [file normalize [file join $::root alpha.sv]]
    set betaPath [file normalize [file join $::root beta.sv]]
    set gammaPath [file normalize [file join $::root gamma.sv]]
    set alpha [dict create name alpha instance u_alpha sourcePath $alphaPath ports {}]
    set beta [dict create name beta instance u_beta sourcePath $betaPath ports {}]
    set gamma [dict create name gamma instance u_gamma sourcePath $gammaPath ports {}]
    set alphaFsm [sequentialFsm alpha {A_IDLE A_RUN}]
    set betaFsm [sequentialFsm beta {B_IDLE B_WAIT B_DONE}]
    set ::svvs::project_tree::sampleModules [list $alpha $beta $gamma]
    set ::svvs::project_tree::fsms [list $alphaFsm $betaFsm]
    set ::svvs::project_tree::projectFiles [list $alphaPath $betaPath $gammaPath]
    set ::svvs::project_tree::projectName selection_test
    set ::svvs::project_tree::projectOpen 1
    ::svvs::project_tree::showBlockLibrary
    ::svvs::project_tree::showProject

    if {[array size ::svvs::project_tree::nodeModules] != 0} {
        error "block-library mappings survived after returning to the Explorer"
    }
    set betaFileItem ""
    foreach item [array names ::svvs::project_tree::projectFileModules] {
        if {[lsearch -exact $::svvs::project_tree::projectFileModules($item) beta] >= 0} {
            set betaFileItem $item
            break
        }
    }
    if {$betaFileItem eq ""} { error "SystemVerilog file was not linked to its module" }
    $::svvs::project_tree::widget selection set $betaFileItem
    ::svvs::project_tree::onSelect
    if {[dict get $::svvs::fsm_viewer::currentFSM module] ne "beta"} {
        error "selecting a SystemVerilog file did not open its module FSM"
    }
    set blockCount [array size ::svvs::canvas_blocks::blocks]
    ::svvs::project_tree::addSelectedToCanvas
    if {[array size ::svvs::canvas_blocks::blocks] != $blockCount} {
        error "a project file was incorrectly added to the block diagram"
    }

    set betaItem ""
    foreach item [array names ::svvs::project_tree::projectNodeModules] {
        if {[dict get $::svvs::project_tree::projectNodeModules($item) name] eq "beta"} {
            set betaItem $item
            break
        }
    }
    if {$betaItem eq ""} { error "project module was not registered in the Explorer" }
    $::svvs::project_tree::widget selection set $betaItem
    ::svvs::project_tree::onSelect
    if {[dict get $::svvs::fsm_viewer::currentFSM module] ne "beta"} {
        error "selecting a module did not open its state machine"
    }
    if {[$::svvs::layout::widgets(notebook) select] ne $::svvs::layout::widgets(fsmTab)} {
        error "module selection did not activate the FSM tab"
    }
    set gammaItem ""
    foreach item [array names ::svvs::project_tree::projectNodeModules] {
        if {[dict get $::svvs::project_tree::projectNodeModules($item) name] eq "gamma"} {
            set gammaItem $item
            break
        }
    }
    $::svvs::project_tree::widget selection set $gammaItem
    ::svvs::project_tree::onSelect
    if {$::svvs::fsm_viewer::currentFSM ne "" ||
        $::svvs::fsm_viewer::emptyMessage ne "No state machine detected in gamma"} {
        error "module without an FSM kept the previously displayed machine"
    }

    set states {
        S_RESET S_READ_0 S_READ_1 S_READ_2 S_READ_3 S_WRITE_0 S_WRITE_1
        S_WRITE_2 S_WRITE_3 S_READ_0_AFTER S_READ_1_AFTER S_READ_2_AFTER
        S_READ_3_AFTER S_IDLE
    }
    ::svvs::fsm_viewer::showFSM [sequentialFsm memory_tester $states]
    update idletasks
    ::svvs::fsm_viewer::redraw
    set canvas $::svvs::fsm_viewer::canvas
    set rectangles {}
    foreach state $states {
        set shape ""
        set text ""
        foreach item [$canvas find withtag "fsm-state:$state"] {
            if {[$canvas type $item] eq "oval"} { set shape $item }
            if {[$canvas type $item] eq "text"} { set text $item }
        }
        if {$shape eq "" || $text eq ""} { error "state was not drawn as a circle: $state" }
        set box [$canvas coords $shape]
        set textBox [$canvas bbox $text]
        if {[lindex $textBox 0] < [lindex $box 0] || [lindex $textBox 2] > [lindex $box 2] ||
            [lindex $textBox 1] < [lindex $box 1] || [lindex $textBox 3] > [lindex $box 3]} {
            error "state name does not fit inside its node: $state"
        }
        lappend rectangles $box
    }
    for {set i 0} {$i < [llength $rectangles]} {incr i} {
        for {set j [expr {$i + 1}]} {$j < [llength $rectangles]} {incr j} {
            if {[rectanglesOverlap [lindex $rectangles $i] [lindex $rectangles $j]]} {
                error "FSM state nodes overlap"
            }
        }
    }
    if {[llength [$canvas find withtag fsm-transition-label]] != 0} {
        error "unconditional transitions still display a default label"
    }

    set editableFsm [dict create name editable_state module editable stateVariable state \
        states {A B} transitions [list [dict create from A to B condition go]]]
    ::svvs::fsm_viewer::showFSM $editableFsm
    update idletasks
    ::svvs::fsm_viewer::redraw
    set stateShape ""
    foreach item [$canvas find withtag fsm-state:A] {
        if {[$canvas type $item] eq "oval"} { set stateShape $item }
    }
    set before [$canvas coords $stateShape]
    set stateX [expr {([lindex $before 0] + [lindex $before 2]) / 2.0}]
    set stateY [expr {([lindex $before 1] + [lindex $before 3]) / 2.0}]
    set stateViewX [expr {$stateX - [$canvas canvasx 0]}]
    set stateViewY [expr {$stateY - [$canvas canvasy 0]}]
    ::svvs::fsm_viewer::editPress $stateViewX $stateViewY
    ::svvs::fsm_viewer::editMove [expr {$stateViewX + 40}] [expr {$stateViewY + 30}]
    ::svvs::fsm_viewer::editRelease
    set stateShape ""
    foreach item [$canvas find withtag fsm-state:A] {
        if {[$canvas type $item] eq "oval"} { set stateShape $item }
    }
    set after [$canvas coords $stateShape]
    if {abs(([lindex $after 0] - [lindex $before 0]) - 40) > 1 ||
        abs(([lindex $after 1] - [lindex $before 1]) - 30) > 1} {
        error "state drag did not preserve its new position"
    }

    set labelItem ""
    foreach item [$canvas find withtag fsm-label:A:B] {
        if {[$canvas type $item] eq "text"} { set labelItem $item }
    }
    set labelBefore [$canvas coords $labelItem]
    set labelViewX [expr {[lindex $labelBefore 0] - [$canvas canvasx 0]}]
    set labelViewY [expr {[lindex $labelBefore 1] - [$canvas canvasy 0]}]
    ::svvs::fsm_viewer::editPress $labelViewX $labelViewY
    ::svvs::fsm_viewer::editMove [expr {$labelViewX + 25}] [expr {$labelViewY - 15}]
    ::svvs::fsm_viewer::editRelease
    set labelItem ""
    foreach item [$canvas find withtag fsm-label:A:B] {
        if {[$canvas type $item] eq "text"} { set labelItem $item }
    }
    set labelAfter [$canvas coords $labelItem]
    if {abs(([lindex $labelAfter 0] - [lindex $labelBefore 0]) - 25) > 1 ||
        abs(([lindex $labelAfter 1] - [lindex $labelBefore 1]) + 15) > 1} {
        error "transition label drag did not preserve its new position: $labelBefore -> $labelAfter"
    }

    set editKey [::svvs::fsm_viewer::fsmKey]
    set ::svvs::fsm_viewer::stateColors($editKey,A) #ff3366
    set ::svvs::fsm_viewer::edgeColors($editKey,A:B) #22cc88
    ::svvs::fsm_viewer::setStateWidth A 6
    ::svvs::fsm_viewer::setEdgeWidth A:B 4
    ::svvs::fsm_viewer::setLabelSize A:B 14
    foreach item [$canvas find withtag fsm-state:A] {
        if {[$canvas type $item] eq "oval"} {
            if {[$canvas itemcget $item -outline] ne "#ff3366" ||
                [$canvas itemcget $item -width] != 6} { error "state style was not applied" }
        }
    }
    set edge [lindex [$canvas find withtag fsm-edge:A:B] 0]
    if {[$canvas itemcget $edge -fill] ne "#22cc88" || [$canvas itemcget $edge -width] != 4} {
        error "transition line style was not applied"
    }
    set labelItem ""
    foreach item [$canvas find withtag fsm-label:A:B] {
        if {[$canvas type $item] eq "text"} { set labelItem $item }
    }
    if {[font actual [$canvas itemcget $labelItem -font] -size] != 14} {
        error "transition label size was not applied"
    }

    set savedEdits [::svvs::fsm_viewer::exportData]
    ::svvs::fsm_viewer::resetEdits
    ::svvs::fsm_viewer::importData $savedEdits
    if {![info exists ::svvs::fsm_viewer::stateOffsets($editKey,A)] ||
        ![info exists ::svvs::fsm_viewer::labelOffsets($editKey,A:B)] ||
        $::svvs::fsm_viewer::stateWidths($editKey,A) != 6 ||
        $::svvs::fsm_viewer::labelSizes($editKey,A:B) != 14} {
        error "FSM visual edits were not restored"
    }
    set projectPath [file join $::root tests fsm_visual_edits.rtlex]
    if {![::svvs::layout::saveProjectTo $projectPath]} { error "project with FSM edits was not saved" }
    ::svvs::fsm_viewer::resetEdits
    if {![::svvs::layout::openProjectFrom $projectPath]} { error "project with FSM edits was not reopened" }
    file delete $projectPath
    if {![info exists ::svvs::fsm_viewer::stateOffsets($editKey,A)] ||
        $::svvs::fsm_viewer::edgeColors($editKey,A:B) ne "#22cc88" ||
        $::svvs::fsm_viewer::labelSizes($editKey,A:B) != 14} {
        error "FSM visual edits were not preserved in the rtlex project"
    }
    puts "FSM viewer UI test: ok"
    destroy .
    set ::fsmTestDone 1
}

after 300 runFsmViewerTest
vwait ::fsmTestDone
