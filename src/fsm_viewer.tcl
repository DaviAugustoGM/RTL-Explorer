namespace eval ::svvs::fsm_viewer {
    variable canvas ""
    variable currentFSM ""
    variable emptyMessage "No state machine detected"
    variable zoom 1.0
    variable panX 0.0
    variable panY 0.0
    variable panLastX 0
    variable panLastY 0
    variable panActive 0
    variable labelSeq 0
    variable stateDrag ""
    variable labelDrag ""
    variable editLastX 0
    variable editLastY 0
    variable stateOffsets
    variable labelOffsets
    variable stateColors
    variable stateWidths
    variable edgeColors
    variable edgeWidths
    variable labelSizes
    variable runtimeStates
    array set stateOffsets {}
    array set labelOffsets {}
    array set stateColors {}
    array set stateWidths {}
    array set edgeColors {}
    array set edgeWidths {}
    array set labelSizes {}
    array set runtimeStates {}
}

proc ::svvs::fsm_viewer::create {parent} {
    variable canvas
    set canvas [canvas $parent.canvas \
        -background [::svvs::theme::color bg] \
        -highlightthickness 0 \
        -borderwidth 0]
    pack $canvas -fill both -expand 1
    bind $canvas <Configure> {after idle ::svvs::fsm_viewer::redraw}
    bind $canvas <MouseWheel> {::svvs::fsm_viewer::onWheel %D %x %y}
    bind $canvas <Button-4> {::svvs::fsm_viewer::onWheel 1 %x %y}
    bind $canvas <Button-5> {::svvs::fsm_viewer::onWheel -1 %x %y}
    bind $canvas <ButtonPress-1> {focus %W; ::svvs::fsm_viewer::editPress %x %y}
    bind $canvas <B1-Motion> {::svvs::fsm_viewer::editMove %x %y}
    bind $canvas <ButtonRelease-1> {::svvs::fsm_viewer::editRelease}
    bind $canvas <ButtonPress-3> {::svvs::fsm_viewer::showContextMenu %X %Y %x %y}
    bind $canvas <ButtonPress-2> {::svvs::fsm_viewer::panStart %x %y}
    bind $canvas <B2-Motion> {::svvs::fsm_viewer::panMove %x %y}
    bind $canvas <ButtonRelease-2> {::svvs::fsm_viewer::panEnd}
    bind $canvas <Double-Button-2> {::svvs::fsm_viewer::resetView}
    bind $canvas <Shift-ButtonPress-1> {focus %W; ::svvs::fsm_viewer::panStart %x %y; break}
    bind $canvas <Shift-B1-Motion> {::svvs::fsm_viewer::panMove %x %y; break}
    bind $canvas <Shift-ButtonRelease-1> {::svvs::fsm_viewer::panEnd; break}
    bind $canvas <Control-plus> {::svvs::fsm_viewer::keyboardZoom 1; break}
    bind $canvas <Control-equal> {::svvs::fsm_viewer::keyboardZoom 1; break}
    bind $canvas <Control-KP_Add> {::svvs::fsm_viewer::keyboardZoom 1; break}
    bind $canvas <Control-minus> {::svvs::fsm_viewer::keyboardZoom -1; break}
    bind $canvas <Control-KP_Subtract> {::svvs::fsm_viewer::keyboardZoom -1; break}
    bind $canvas <Control-Key-0> {::svvs::fsm_viewer::resetView; break}
    bind $canvas <Left> {::svvs::fsm_viewer::keyboardPan -40 0; break}
    bind $canvas <Right> {::svvs::fsm_viewer::keyboardPan 40 0; break}
    bind $canvas <Up> {::svvs::fsm_viewer::keyboardPan 0 -40; break}
    bind $canvas <Down> {::svvs::fsm_viewer::keyboardPan 0 40; break}
    ::svvs::fsm_viewer::showEmpty
    return $canvas
}

proc ::svvs::fsm_viewer::fsmKey {} {
    variable currentFSM
    if {$currentFSM eq ""} { return "" }
    return "[dict get $currentFSM module]|[dict get $currentFSM stateVariable]"
}

proc ::svvs::fsm_viewer::tagValueAt {x y prefixes} {
    variable canvas
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]
    set items [$canvas find overlapping [expr {$cx - 4}] [expr {$cy - 4}] \
        [expr {$cx + 4}] [expr {$cy + 4}]]
    foreach item [lreverse $items] {
        foreach tag [$canvas gettags $item] {
            foreach prefix $prefixes {
                if {[string match "$prefix*" $tag]} { return [list $prefix [string range $tag [string length $prefix] end]] }
            }
        }
    }
    return ""
}

proc ::svvs::fsm_viewer::editPress {x y} {
    variable stateDrag
    variable labelDrag
    variable editLastX
    variable editLastY
    variable canvas
    set stateDrag ""
    set labelDrag ""
    set target [::svvs::fsm_viewer::tagValueAt $x $y {fsm-state: fsm-label:}]
    if {$target eq ""} {
        ::svvs::fsm_viewer::panStart $x $y
        return
    }
    lassign $target prefix value
    if {$prefix eq "fsm-state:"} { set stateDrag $value } else { set labelDrag $value }
    set editLastX $x
    set editLastY $y
    $canvas configure -cursor hand2
}

proc ::svvs::fsm_viewer::editMove {x y} {
    variable stateDrag
    variable labelDrag
    variable editLastX
    variable editLastY
    variable zoom
    variable stateOffsets
    variable labelOffsets
    if {$stateDrag eq "" && $labelDrag eq ""} {
        ::svvs::fsm_viewer::panMove $x $y
        return
    }
    set dx [expr {($x - $editLastX) / $zoom}]
    set dy [expr {($y - $editLastY) / $zoom}]
    set key [::svvs::fsm_viewer::fsmKey]
    if {$stateDrag ne ""} {
        set arrayKey "$key,$stateDrag"
        set offset [expr {[info exists stateOffsets($arrayKey)] ? $stateOffsets($arrayKey) : {0 0}}]
        set stateOffsets($arrayKey) [list [expr {[lindex $offset 0] + $dx}] [expr {[lindex $offset 1] + $dy}]]
    } else {
        set arrayKey "$key,$labelDrag"
        set offset [expr {[info exists labelOffsets($arrayKey)] ? $labelOffsets($arrayKey) : {0 0}}]
        set labelOffsets($arrayKey) [list [expr {[lindex $offset 0] + $dx}] [expr {[lindex $offset 1] + $dy}]]
    }
    set editLastX $x
    set editLastY $y
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::editRelease {} {
    variable stateDrag
    variable labelDrag
    variable canvas
    if {$stateDrag ne ""} { ::svvs::console::log "Estado reposicionado." ok }
    if {$labelDrag ne ""} { ::svvs::console::log "Condicao de transicao reposicionada." ok }
    set stateDrag ""
    set labelDrag ""
    ::svvs::fsm_viewer::panEnd
    if {$canvas ne "" && [winfo exists $canvas]} { $canvas configure -cursor "" }
}

proc ::svvs::fsm_viewer::showContextMenu {rootX rootY x y} {
    variable stateColors
    variable stateWidths
    variable edgeColors
    variable edgeWidths
    variable labelSizes
    set target [::svvs::fsm_viewer::tagValueAt $x $y {fsm-state: fsm-label: fsm-edge:}]
    if {$target eq ""} { return }
    lassign $target prefix value
    catch {destroy .fsmContextMenu}
    menu .fsmContextMenu -tearoff 0 \
        -background [::svvs::theme::color panel] -foreground [::svvs::theme::color text] \
        -activebackground [::svvs::theme::color selected] -activeforeground white
    if {$prefix eq "fsm-state:"} {
        .fsmContextMenu add command -label "Circle color..." \
            -command [list ::svvs::fsm_viewer::chooseStateColor $value]
        menu .fsmContextMenu.width -tearoff 0
        foreach width {1 2 3 4 6 8} {
            .fsmContextMenu.width add command -label $width \
                -command [list ::svvs::fsm_viewer::setStateWidth $value $width]
        }
        .fsmContextMenu add cascade -label "Circle thickness" -menu .fsmContextMenu.width
        .fsmContextMenu add separator
        .fsmContextMenu add command -label "Reset position" \
            -command [list ::svvs::fsm_viewer::resetStatePosition $value]
        .fsmContextMenu add command -label "Reset style" \
            -command [list ::svvs::fsm_viewer::resetStateStyle $value]
    } else {
        .fsmContextMenu add command -label "Transition color..." \
            -command [list ::svvs::fsm_viewer::chooseEdgeColor $value]
        menu .fsmContextMenu.width -tearoff 0
        foreach width {1 2 3 4 6 8} {
            .fsmContextMenu.width add command -label $width \
                -command [list ::svvs::fsm_viewer::setEdgeWidth $value $width]
        }
        .fsmContextMenu add cascade -label "Line thickness" -menu .fsmContextMenu.width
        menu .fsmContextMenu.font -tearoff 0
        foreach size {7 8 9 10 12 14 16 18} {
            .fsmContextMenu.font add command -label $size \
                -command [list ::svvs::fsm_viewer::setLabelSize $value $size]
        }
        .fsmContextMenu add cascade -label "Condition text size" -menu .fsmContextMenu.font
        .fsmContextMenu add separator
        .fsmContextMenu add command -label "Reset label position" \
            -command [list ::svvs::fsm_viewer::resetLabelPosition $value]
        .fsmContextMenu add command -label "Reset transition style" \
            -command [list ::svvs::fsm_viewer::resetEdgeStyle $value]
    }
    tk_popup .fsmContextMenu $rootX $rootY
}

proc ::svvs::fsm_viewer::chooseStateColor {state} {
    variable stateColors
    set key "[::svvs::fsm_viewer::fsmKey],$state"
    set initial [expr {[info exists stateColors($key)] ? $stateColors($key) : [::svvs::theme::color accent]}]
    set color [tk_chooseColor -title "State circle color" -initialcolor $initial]
    if {$color ne ""} { set stateColors($key) $color; ::svvs::fsm_viewer::redraw }
}

proc ::svvs::fsm_viewer::chooseEdgeColor {edge} {
    variable edgeColors
    set key "[::svvs::fsm_viewer::fsmKey],$edge"
    set initial [expr {[info exists edgeColors($key)] ? $edgeColors($key) : [::svvs::theme::color wire]}]
    set color [tk_chooseColor -title "Transition line color" -initialcolor $initial]
    if {$color ne ""} { set edgeColors($key) $color; ::svvs::fsm_viewer::redraw }
}

proc ::svvs::fsm_viewer::setStateWidth {state width} {
    variable stateWidths
    set stateWidths([::svvs::fsm_viewer::fsmKey],$state) $width
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::setEdgeWidth {edge width} {
    variable edgeWidths
    set edgeWidths([::svvs::fsm_viewer::fsmKey],$edge) $width
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::setLabelSize {edge size} {
    variable labelSizes
    set labelSizes([::svvs::fsm_viewer::fsmKey],$edge) $size
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::resetStatePosition {state} {
    variable stateOffsets
    catch {unset stateOffsets([::svvs::fsm_viewer::fsmKey],$state)}
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::resetLabelPosition {edge} {
    variable labelOffsets
    catch {unset labelOffsets([::svvs::fsm_viewer::fsmKey],$edge)}
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::resetStateStyle {state} {
    variable stateColors
    variable stateWidths
    set key "[::svvs::fsm_viewer::fsmKey],$state"
    catch {unset stateColors($key)}
    catch {unset stateWidths($key)}
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::resetEdgeStyle {edge} {
    variable edgeColors
    variable edgeWidths
    variable labelSizes
    set key "[::svvs::fsm_viewer::fsmKey],$edge"
    catch {unset edgeColors($key)}
    catch {unset edgeWidths($key)}
    catch {unset labelSizes($key)}
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::exportData {} {
    set result {}
    foreach name {stateOffsets labelOffsets stateColors stateWidths edgeColors edgeWidths labelSizes} {
        upvar 0 ::svvs::fsm_viewer::$name values
        dict set result $name [array get values]
    }
    return $result
}

proc ::svvs::fsm_viewer::importData {data} {
    foreach name {stateOffsets labelOffsets stateColors stateWidths edgeColors edgeWidths labelSizes} {
        upvar 0 ::svvs::fsm_viewer::$name values
        array unset values
        array set values {}
        if {[dict exists $data $name]} { array set values [dict get $data $name] }
    }
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::resetEdits {} {
    foreach name {stateOffsets labelOffsets stateColors stateWidths edgeColors edgeWidths labelSizes} {
        upvar 0 ::svvs::fsm_viewer::$name values
        array unset values
        array set values {}
    }
}

proc ::svvs::fsm_viewer::showEmpty {{message "No state machine detected"}} {
    variable currentFSM
    variable emptyMessage
    ::svvs::fsm_viewer::resetView 0
    set currentFSM ""
    set emptyMessage $message
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::showFSM {fsm} {
    variable currentFSM
    variable emptyMessage
    if {$currentFSM eq "" ||
        [dict get $currentFSM name] ne [dict get $fsm name]} {
        ::svvs::fsm_viewer::resetView 0
    }
    set currentFSM $fsm
    set emptyMessage "No state machine detected"
    ::svvs::fsm_viewer::redraw
}

proc ::svvs::fsm_viewer::setRuntimeValue {fsm value} {
    variable runtimeStates
    if {![string is integer -strict $value]} { return }
    set state ""
    if {[dict exists $fsm stateValues]} {
        dict for {candidate encoded} [dict get $fsm stateValues] {
            if {$encoded == $value} { set state $candidate; break }
        }
    }
    if {$state eq "" && $value >= 0 && $value < [llength [dict get $fsm states]]} {
        set state [lindex [dict get $fsm states] $value]
    }
    if {$state eq ""} { return }
    set runtimeStates([dict get $fsm name]) $state
    ::svvs::fsm_viewer::paintRuntimeState
}

proc ::svvs::fsm_viewer::paintRuntimeState {} {
    variable canvas
    variable currentFSM
    variable runtimeStates
    variable stateColors
    variable stateWidths
    variable zoom
    if {$canvas eq "" || ![winfo exists $canvas] || $currentFSM eq ""} { return }
    set active ""
    set key [dict get $currentFSM name]
    if {[info exists runtimeStates($key)]} { set active $runtimeStates($key) }
    set editKey [::svvs::fsm_viewer::fsmKey]
    foreach state [dict get $currentFSM states] {
        set styleKey "$editKey,$state"
        set outline [expr {[info exists stateColors($styleKey)] ? $stateColors($styleKey) : [::svvs::theme::color accent]}]
        set baseWidth [expr {[info exists stateWidths($styleKey)] ? $stateWidths($styleKey) : 2}]
        foreach item [$canvas find withtag "fsm-state:$state"] {
            if {[$canvas type $item] in {rectangle oval}} {
                $canvas itemconfigure $item \
                    -fill [expr {$state eq $active ? "#244b3a" : [::svvs::theme::color block]}] \
                    -outline $outline \
                    -width [expr {max(1, round(max($baseWidth, $state eq $active ? 4 : $baseWidth) * $zoom))}]
            }
        }
    }
}

proc ::svvs::fsm_viewer::resetView {{redrawNow 1}} {
    variable zoom
    variable panX
    variable panY
    variable panActive
    set zoom 1.0
    set panX 0.0
    set panY 0.0
    set panActive 0
    if {$redrawNow} {
        ::svvs::fsm_viewer::redraw
    }
}

proc ::svvs::fsm_viewer::onWheel {delta x y} {
    variable canvas
    variable zoom
    variable panX
    variable panY
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return
    }
    set factor [expr {$delta < 0 ? 0.92 : 1.08}]
    set nextZoom [expr {$zoom * $factor}]
    if {$nextZoom < 0.25 || $nextZoom > 3.0} {
        return
    }
    set centerX [expr {[winfo width $canvas] / 2.0}]
    set centerY [expr {[winfo height $canvas] / 2.0}]
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]
    set panX [expr {($factor * $panX) + ((1.0 - $factor) * ($cx - $centerX))}]
    set panY [expr {($factor * $panY) + ((1.0 - $factor) * ($cy - $centerY))}]
    set zoom $nextZoom
    $canvas scale all $cx $cy $factor $factor
    ::svvs::fsm_viewer::updateVisualScale
    ::svvs::fsm_viewer::paintRuntimeState
    $canvas configure -scrollregion [$canvas bbox all]
}

proc ::svvs::fsm_viewer::keyboardZoom {direction} {
    variable canvas
    if {$canvas eq "" || ![winfo exists $canvas]} { return }
    ::svvs::fsm_viewer::onWheel $direction \
        [expr {[winfo width $canvas] / 2}] [expr {[winfo height $canvas] / 2}]
}

proc ::svvs::fsm_viewer::keyboardPan {dx dy} {
    variable canvas
    variable panX
    variable panY
    if {$canvas eq "" || ![winfo exists $canvas]} { return }
    $canvas move all [expr {-$dx}] [expr {-$dy}]
    set panX [expr {$panX - $dx}]
    set panY [expr {$panY - $dy}]
    $canvas configure -scrollregion [$canvas bbox all]
}

proc ::svvs::fsm_viewer::panStart {x y} {
    variable canvas
    variable panLastX
    variable panLastY
    variable panActive
    set panLastX $x
    set panLastY $y
    set panActive 1
    $canvas configure -cursor fleur
}

proc ::svvs::fsm_viewer::panMove {x y} {
    variable canvas
    variable panX
    variable panY
    variable panLastX
    variable panLastY
    variable panActive
    if {!$panActive} {
        return
    }
    set dx [expr {$x - $panLastX}]
    set dy [expr {$y - $panLastY}]
    $canvas move all $dx $dy
    set panX [expr {$panX + $dx}]
    set panY [expr {$panY + $dy}]
    set panLastX $x
    set panLastY $y
    $canvas configure -scrollregion [$canvas bbox all]
}

proc ::svvs::fsm_viewer::panEnd {} {
    variable canvas
    variable panActive
    set panActive 0
    if {$canvas ne "" && [winfo exists $canvas]} {
        $canvas configure -cursor ""
    }
}

proc ::svvs::fsm_viewer::scaledSize {base minimum maximum} {
    variable zoom
    set size [expr {int(round($base * $zoom))}]
    return [expr {max($minimum, min($maximum, $size))}]
}

proc ::svvs::fsm_viewer::updateVisualScale {} {
    variable canvas
    variable zoom
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return
    }
    foreach item [$canvas find withtag fsm-title] {
        $canvas itemconfigure $item -font [list {Segoe UI} \
            [::svvs::fsm_viewer::scaledSize 11 7 24] bold]
    }
    foreach item [$canvas find withtag fsm-state] {
        if {[$canvas type $item] eq "text"} {
            $canvas itemconfigure $item -font [list {Segoe UI} \
                [::svvs::fsm_viewer::scaledSize 10 6 22] bold]
        } elseif {[$canvas type $item] in {rectangle oval}} {
            set baseWidth 2
            set widthTag [::svvs::fsm_viewer::tagWithPrefix [$canvas gettags $item] "fsm-state-width:"]
            if {$widthTag ne ""} { set baseWidth [string range $widthTag [string length "fsm-state-width:"] end] }
            $canvas itemconfigure $item -width [expr {max(1, round($baseWidth * $zoom))}]
        }
    }
    foreach item [$canvas find withtag fsm-transition-label] {
        set baseSize 8
        set sizeTag [::svvs::fsm_viewer::tagWithPrefix [$canvas gettags $item] "fsm-label-size:"]
        if {$sizeTag ne ""} { set baseSize [string range $sizeTag [string length "fsm-label-size:"] end] }
        $canvas itemconfigure $item -font [list Consolas \
            [::svvs::fsm_viewer::scaledSize $baseSize 5 28]]
    }
    foreach item [$canvas find withtag fsm-transition] {
        if {[$canvas type $item] eq "line"} {
            set baseWidth 2
            set widthTag [::svvs::fsm_viewer::tagWithPrefix [$canvas gettags $item] "fsm-edge-width:"]
            if {$widthTag ne ""} { set baseWidth [string range $widthTag [string length "fsm-edge-width:"] end] }
            set lineWidth [expr {max(1, round($baseWidth * $zoom))}]
            set arrowA [expr {max(5, round(8 * $zoom))}]
            set arrowB [expr {max(6, round(10 * $zoom))}]
            set arrowC [expr {max(3, round(4 * $zoom))}]
            $canvas itemconfigure $item -width $lineWidth \
                -arrowshape [list $arrowA $arrowB $arrowC]
        }
    }
    ::svvs::fsm_viewer::updateLabelBackgrounds
}

proc ::svvs::fsm_viewer::tagWithPrefix {tags prefix} {
    foreach tag $tags {
        if {[string match "$prefix*" $tag]} {
            return $tag
        }
    }
    return ""
}

proc ::svvs::fsm_viewer::createTransitionLabel {x y text extraTags {baseSize 8}} {
    variable canvas
    variable labelSeq
    set id [incr labelSeq]
    set idTag "fsm-label-id:$id"
    set textItem [$canvas create text $x $y \
        -text $text \
        -fill [::svvs::theme::color muted] \
        -font [list Consolas $baseSize] \
        -anchor center \
        -tags [concat [list fsm-transition-label $idTag "fsm-label-size:$baseSize"] $extraTags]]
    set box [$canvas bbox $textItem]
    set background [$canvas create rectangle \
        [expr {[lindex $box 0] - 4}] [expr {[lindex $box 1] - 2}] \
        [expr {[lindex $box 2] + 4}] [expr {[lindex $box 3] + 2}] \
        -fill [::svvs::theme::color bg] \
        -outline "" \
        -tags [concat [list fsm-label-background $idTag] $extraTags]]
    $canvas lower $background $textItem
    return $textItem
}

proc ::svvs::fsm_viewer::updateLabelBackgrounds {} {
    variable canvas
    foreach background [$canvas find withtag fsm-label-background] {
        set idTag [::svvs::fsm_viewer::tagWithPrefix [$canvas gettags $background] "fsm-label-id:"]
        if {$idTag eq ""} {
            continue
        }
        set textItem ""
        foreach item [$canvas find withtag $idTag] {
            if {[$canvas type $item] eq "text"} {
                set textItem $item
                break
            }
        }
        if {$textItem eq ""} {
            continue
        }
        set box [$canvas bbox $textItem]
        $canvas coords $background \
            [expr {[lindex $box 0] - 4}] [expr {[lindex $box 1] - 2}] \
            [expr {[lindex $box 2] + 4}] [expr {[lindex $box 3] + 2}]
        $canvas lower $background $textItem
    }
}

proc ::svvs::fsm_viewer::layoutCells {states transitions} {
    set count [llength $states]
    set columns [expr {max(1, int(ceil(sqrt(double($count)))))}]
    set path {}
    set visited {}
    set current [lindex $states 0]
    while {$current ne "" && ![dict exists $visited $current]} {
        lappend path $current
        dict set visited $current 1
        set next ""
        foreach transition $transitions {
            if {[dict get $transition from] ne $current} {
                continue
            }
            set candidate [dict get $transition to]
            if {$candidate ne $current && ![dict exists $visited $candidate]} {
                set next $candidate
                break
            }
        }
        set current $next
    }

    set remaining {}
    foreach state $states {
        if {![dict exists $visited $state]} {
            lappend remaining $state
        }
    }

    set cells {}
    set occupied {}
    set topCount [expr {min($columns, [llength $path])}]
    for {set i 0} {$i < $topCount} {incr i} {
        set state [lindex $path $i]
        dict set cells $state [list $i 0]
        dict set occupied "$i,0" 1
    }

    set bottomPath [lrange $path $topCount end]
    set startColumn [expr {$columns - 1 - min([llength $remaining], 1)}]
    set row 1
    foreach state $bottomPath {
        while {$startColumn < 0 || [dict exists $occupied "$startColumn,$row"]} {
            incr row
            set startColumn [expr {$columns - 1}]
        }
        dict set cells $state [list $startColumn $row]
        dict set occupied "$startColumn,$row" 1
        incr startColumn -1
    }

    foreach state $remaining {
        set placed 0
        for {set row 1} {!$placed} {incr row} {
            for {set column [expr {$columns - 1}]} {$column >= 0} {incr column -1} {
                if {![dict exists $occupied "$column,$row"]} {
                    dict set cells $state [list $column $row]
                    dict set occupied "$column,$row" 1
                    set placed 1
                    break
                }
            }
        }
    }
    return [dict create columns $columns cells $cells]
}

proc ::svvs::fsm_viewer::laneOffset {keys key} {
    set count [llength $keys]
    set index [lsearch -exact $keys $key]
    if {$index < 0 || $count <= 1} {
        return 0
    }
    return [expr {($index - (($count - 1) / 2.0)) * 18.0}]
}

proc ::svvs::fsm_viewer::redraw {} {
    variable canvas
    variable currentFSM
    variable labelSeq
    variable emptyMessage
    variable stateOffsets
    variable labelOffsets
    variable stateColors
    variable stateWidths
    variable edgeColors
    variable edgeWidths
    variable labelSizes
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return
    }
    $canvas delete all
    set labelSeq 0
    set width [winfo width $canvas]
    set height [winfo height $canvas]
    if {$width < 10} { set width 760 }
    if {$height < 10} { set height 560 }

    if {$currentFSM eq ""} {
        $canvas create text [expr {$width / 2.0}] [expr {$height / 2.0}] \
            -text $emptyMessage \
            -fill [::svvs::theme::color muted] \
            -font {{Segoe UI} 11}
        return
    }

    set states [dict get $currentFSM states]
    if {[llength $states] == 0} {
        ::svvs::fsm_viewer::showEmpty
        return
    }

    $canvas create text 22 20 \
        -text "[dict get $currentFSM module] / [dict get $currentFSM stateVariable]" \
        -fill [::svvs::theme::color text] \
        -font {{Segoe UI} 11 bold} \
        -anchor nw \
        -tags fsm-title

    set count [llength $states]
    set transitions [dict get $currentFSM transitions]
    set layout [::svvs::fsm_viewer::layoutCells $states $transitions]
    set columns [dict get $layout columns]
    set cells [dict get $layout cells]
    set rows 1
    set longestState 0
    foreach state $states {
        set longestState [expr {max($longestState, [string length $state])}]
        set cell [dict get $cells $state]
        set rows [expr {max($rows, [lindex $cell 1] + 1)}]
    }
    set stateDiameter [expr {max(92.0, min(176.0, 38.0 + ($longestState * 8.0)))}]
    set stateRadius [expr {$stateDiameter / 2.0}]
    set stepX [expr {$stateDiameter + 58.0}]
    set stepY [expr {$stateDiameter + 58.0}]
    set layoutWidth [expr {($columns - 1) * $stepX}]
    set layoutHeight [expr {($rows - 1) * $stepY}]
    set left [expr {($width - $layoutWidth) / 2.0}]
    set top [expr {max(86.0, (($height - $layoutHeight) / 2.0) + 18.0)}]
    set editKey [::svvs::fsm_viewer::fsmKey]

    array set positions {}
    foreach state $states {
        lassign [dict get $cells $state] column row
        set x [expr {$columns > 1 ? $left + ($column * $stepX) : $width / 2.0}]
        set y [expr {$rows > 1 ? $top + ($row * $stepY) : $height / 2.0}]
        set offsetKey "$editKey,$state"
        if {[info exists stateOffsets($offsetKey)]} {
            set x [expr {$x + [lindex $stateOffsets($offsetKey) 0]}]
            set y [expr {$y + [lindex $stateOffsets($offsetKey) 1]}]
        }
        set positions($state) [list $x $y]
    }

    array set edgeConditions {}
    foreach transition $transitions {
        set from [dict get $transition from]
        set to [dict get $transition to]
        if {![info exists positions($from)] || ![info exists positions($to)]} {
            continue
        }
        set key "$from|$to"
        set condition [dict get $transition condition]
        if {![info exists edgeConditions($key)]} {
            set edgeConditions($key) {}
        }
        if {[lsearch -exact $edgeConditions($key) $condition] < 0} {
            lappend edgeConditions($key) $condition
        }
    }

    array set outgoingLanes {}
    array set incomingLanes {}
    foreach key [lsort [array names edgeConditions]] {
        lassign [split $key |] from to
        if {$from eq $to} {
            continue
        }
        lassign $positions($from) fx fy
        lassign $positions($to) tx ty
        set orientation [expr {abs($ty - $fy) < 60 ? "H" : "V"}]
        lappend outgoingLanes($from,$orientation) $key
        lappend incomingLanes($to,$orientation) $key
    }

    foreach key [lsort [array names edgeConditions]] {
        lassign [split $key |] from to
        lassign $positions($from) fx fy
        lassign $positions($to) tx ty
        set label [join $edgeConditions($key) " / "]
        set edgeName "$from:$to"
        set styleKey "$editKey,$edgeName"
        if {$from eq $to} {
            set coords [list \
                [expr {$fx + $stateRadius}] $fy \
                [expr {$fx + $stateRadius + 30}] $fy \
                [expr {$fx + $stateRadius + 30}] [expr {$fy - $stateRadius - 30}] \
                $fx [expr {$fy - $stateRadius - 30}] \
                $fx [expr {$fy - $stateRadius}]]
            set lx [expr {$fx + ($stateRadius / 2.0)}]
            set ly [expr {$fy - $stateRadius - 40}]
        } else {
            set dx [expr {$tx - $fx}]
            set dy [expr {$ty - $fy}]
            if {abs($dy) < 60} {
                set startOffset [::svvs::fsm_viewer::laneOffset $outgoingLanes($from,H) $key]
                set endOffset [::svvs::fsm_viewer::laneOffset $incomingLanes($to,H) $key]
                set sx [expr {$fx + ($dx >= 0 ? $stateRadius : -$stateRadius)}]
                set sy [expr {$fy + $startOffset}]
                set ex [expr {$tx + ($dx >= 0 ? -$stateRadius : $stateRadius)}]
                set ey [expr {$ty + $endOffset}]
                set mid [expr {($sx + $ex) / 2.0}]
                set coords [list $sx $sy $mid $sy $mid $ey $ex $ey]
                set lx $mid
                set ly [expr {($sy + $ey) / 2.0 - 11}]
            } else {
                set startOffset [::svvs::fsm_viewer::laneOffset $outgoingLanes($from,V) $key]
                set endOffset [::svvs::fsm_viewer::laneOffset $incomingLanes($to,V) $key]
                set sx [expr {$fx + $startOffset}]
                set sy [expr {$fy + ($dy >= 0 ? $stateRadius : -$stateRadius)}]
                set ex [expr {$tx + $endOffset}]
                set ey [expr {$ty + ($dy >= 0 ? -$stateRadius : $stateRadius)}]
                set mid [expr {($sy + $ey) / 2.0}]
                set coords [list $sx $sy $sx $mid $ex $mid $ex $ey]
                if {abs($ex - $sx) < 24} {
                    set lx [expr {$sx + 26}]
                    set ly $mid
                } else {
                    set lx [expr {($sx + $ex) / 2.0}]
                    set ly [expr {$mid - 13}]
                }
            }
        }
        if {[info exists labelOffsets($styleKey)]} {
            set lx [expr {$lx + [lindex $labelOffsets($styleKey) 0]}]
            set ly [expr {$ly + [lindex $labelOffsets($styleKey) 1]}]
        }
        set edgeColor [expr {[info exists edgeColors($styleKey)] ? $edgeColors($styleKey) : [::svvs::theme::color wire]}]
        set edgeWidth [expr {[info exists edgeWidths($styleKey)] ? $edgeWidths($styleKey) : 2}]
        set labelSize [expr {[info exists labelSizes($styleKey)] ? $labelSizes($styleKey) : 8}]
        $canvas create line {*}$coords \
            -fill $edgeColor \
            -width $edgeWidth \
            -arrow last \
            -smooth true \
            -splinesteps 24 \
            -tags [list fsm-transition "fsm-edge:$from:$to" "fsm-edge-width:$edgeWidth"]
        if {$label ni {"" default}} {
            ::svvs::fsm_viewer::createTransitionLabel $lx $ly $label \
                [list "fsm-label:$from:$to"] $labelSize
        }
    }

    if {[dict exists $currentFSM initialState]} {
        set initialState [dict get $currentFSM initialState]
        if {[info exists positions($initialState)]} {
            lassign $positions($initialState) ix iy
            set markerX [expr {$ix - $stateRadius - 24}]
            set markerY $iy
            $canvas create oval \
                [expr {$markerX - 9}] [expr {$markerY - 9}] \
                [expr {$markerX + 9}] [expr {$markerY + 9}] \
                -fill [::svvs::theme::color accent] \
                -outline [::svvs::theme::color accent] \
                -tags [list fsm-initial-marker "fsm-initial:$initialState"]
            $canvas create line \
                [expr {$markerX + 10}] $markerY \
                [expr {$markerX + 20}] [expr {$markerY - 20}] \
                [expr {$ix - $stateRadius}] $iy \
                -fill [::svvs::theme::color accent] \
                -width 2 \
                -arrow last \
                -smooth true \
                -splinesteps 24 \
                -tags [list fsm-transition "fsm-reset:$initialState"]
            set resetLabel "reset"
            if {[dict exists $currentFSM resetCondition]} {
                set resetLabel [dict get $currentFSM resetCondition]
            }
            ::svvs::fsm_viewer::createTransitionLabel \
                [expr {$markerX + 10}] [expr {$markerY - 42}] $resetLabel \
                [list "fsm-reset-label:$initialState"]
        }
    }

    foreach state $states {
        lassign $positions($state) x y
        set styleKey "$editKey,$state"
        set stateColor [expr {[info exists stateColors($styleKey)] ? $stateColors($styleKey) : [::svvs::theme::color accent]}]
        set stateWidth [expr {[info exists stateWidths($styleKey)] ? $stateWidths($styleKey) : 2}]
        $canvas create oval \
            [expr {$x - $stateRadius}] [expr {$y - $stateRadius}] \
            [expr {$x + $stateRadius}] [expr {$y + $stateRadius}] \
            -fill [::svvs::theme::color block] \
            -outline $stateColor \
            -width $stateWidth \
            -tags [list fsm-state "fsm-state:$state" "fsm-state-width:$stateWidth"]
        $canvas create text $x $y \
            -text $state \
            -fill [::svvs::theme::color text] \
            -font {{Segoe UI} 10 bold} \
            -tags [list fsm-state "fsm-state:$state"]
    }
    variable zoom
    variable panX
    variable panY
    set centerX [expr {$width / 2.0}]
    set centerY [expr {$height / 2.0}]
    if {$zoom != 1.0} {
        $canvas scale all $centerX $centerY $zoom $zoom
    }
    if {$panX != 0.0 || $panY != 0.0} {
        $canvas move all $panX $panY
    }
    ::svvs::fsm_viewer::updateVisualScale
    ::svvs::fsm_viewer::paintRuntimeState
    $canvas configure -scrollregion [$canvas bbox all]
}
