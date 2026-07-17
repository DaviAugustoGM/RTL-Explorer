namespace eval ::svvs::diagram_simulation {
    variable active 0
    variable model ""
    variable editSignal ""
    variable editValue 0
    variable values
    variable portSignals
    variable signalWidths
    array set values {}
    array set portSignals {}
    array set signalWidths {}
}

proc ::svvs::diagram_simulation::activate {newModel} {
    variable active
    variable model
    variable portSignals
    variable signalWidths
    set model $newModel
    set active 1
    array unset portSignals
    array unset signalWidths
    array set portSignals {}
    array set signalWidths {}

    if {$::svvs::canvas_connections::simplifiedMode} {
        set ::svvs::canvas_connections::simplifiedMode 0
        ::svvs::layout::setToolbarActive "Simple Wires" 0
        ::svvs::canvas_connections::refreshDisplay
    }

    set netSignals {}
    foreach signal [dict get $model inputs] {
        set name [dict get $signal name]
        set signalWidths($name) [dict get $signal width]
        dict set netSignals [dict get $signal net] $name
    }
    foreach signal [dict get $model outputs] {
        set name [dict get $signal name]
        set signalWidths($name) [dict get $signal width]
        dict set netSignals [dict get $signal net] $name
    }
    foreach net [dict get $model nets] {
        set netName [dict get $net name]
        if {![dict exists $netSignals $netName]} { continue }
        set signalName [dict get $netSignals $netName]
        foreach record [dict get $net members] {
            set portSignals([dict get $record tag]) $signalName
        }
    }
    ::svvs::layout::setToolbarActive "Run" 1
    ::svvs::diagram_simulation::showDiagram
    ::svvs::diagram_simulation::redraw
}

proc ::svvs::diagram_simulation::showDiagram {} {
    if {[info exists ::svvs::layout::widgets(notebook)] &&
        [info exists ::svvs::layout::widgets(canvasTab)]} {
        $::svvs::layout::widgets(notebook) select $::svvs::layout::widgets(canvasTab)
    }
}

proc ::svvs::diagram_simulation::deactivate {} {
    variable active
    set active 0
    set canvas $::svvs::canvas_blocks::canvas
    if {$canvas ne "" && [winfo exists $canvas]} {
        $canvas delete simulation-overlay
        foreach portTag [array names ::svvs::canvas_blocks::tagToPort] {
            set port $::svvs::canvas_blocks::tagToPort($portTag)
            set color [expr {[dict get $port direction] eq "output" ?
                [::svvs::theme::color portOut] : [::svvs::theme::color portIn]}]
            foreach item [$canvas find withtag $portTag] {
                if {[lsearch -exact [$canvas gettags $item] port] >= 0} {
                    $canvas itemconfigure $item -fill $color -outline $color
                }
            }
        }
        ::svvs::canvas_connections::refreshDisplay
    }
    ::svvs::layout::setToolbarActive "Run" 0
}

proc ::svvs::diagram_simulation::updateValues {pairs} {
    variable active
    variable values
    foreach pair $pairs {
        set equals [string first = $pair]
        if {$equals < 1} { continue }
        set name [string range $pair 0 [expr {$equals - 1}]]
        set values($name) [string range $pair [expr {$equals + 1}] end]
    }
    if {$active} { ::svvs::diagram_simulation::redraw }
}

proc ::svvs::diagram_simulation::signalValue {name} {
    variable values
    if {[info exists values($name)]} { return $values($name) }
    return x
}

proc ::svvs::diagram_simulation::integerValue {value} {
    set value [string trim $value]
    if {[string is integer -strict $value]} {
        return $value
    }
    if {[regexp -nocase {^0x([0-9a-f]+)$} $value -> hex]} {
        scan $hex %x parsed
        return $parsed
    }
    if {[regexp -nocase {^0b([01]+)$} $value -> bits]} {
        set parsed 0
        foreach bit [split $bits ""] {
            set parsed [expr {($parsed << 1) | $bit}]
        }
        return $parsed
    }
    return ""
}

proc ::svvs::diagram_simulation::rangeSlice {range portWidth} {
    if {$range eq ""} {
        return [list 0 $portWidth]
    }
    if {![regexp {^\s*([0-9]+)(?:\s*:\s*([0-9]+))?\s*$} $range -> left right]} {
        return [list 0 $portWidth]
    }
    if {$right eq ""} {
        set right $left
    }
    set low [expr {$left < $right ? $left : $right}]
    set width [expr {abs($left - $right) + 1}]
    return [list $low $width]
}

proc ::svvs::diagram_simulation::portWidth {portTag} {
    if {[catch {set info [::svvs::canvas_blocks::portInfo $portTag]}]} {
        return 1
    }
    set port [dict get $info port]
    if {[dict exists $port width]} {
        return [dict get $port width]
    }
    return 1
}

proc ::svvs::diagram_simulation::sliceValue {value range portWidth} {
    if {$range eq ""} {
        return $value
    }
    set number [::svvs::diagram_simulation::integerValue $value]
    if {$number eq ""} {
        return $value
    }
    lassign [::svvs::diagram_simulation::rangeSlice $range $portWidth] low width
    if {$width <= 0} {
        return $value
    }
    set mask [expr {(1 << $width) - 1}]
    return [expr {($number >> $low) & $mask}]
}

proc ::svvs::diagram_simulation::connectionValue {connection} {
    variable portSignals

    foreach {endpoint rangeKey} {from fromRange to toRange} {
        set portTag [dict get $connection $endpoint]
        if {![info exists portSignals($portTag)]} {
            continue
        }
        set range [::svvs::canvas_connections::connectionField $connection $rangeKey]
        if {$range eq ""} {
            continue
        }
        set value [::svvs::diagram_simulation::signalValue $portSignals($portTag)]
        set width [::svvs::diagram_simulation::portWidth $portTag]
        return [::svvs::diagram_simulation::sliceValue $value $range $width]
    }

    foreach endpoint {from to} {
        set portTag [dict get $connection $endpoint]
        if {![info exists portSignals($portTag)]} {
            continue
        }
        return [::svvs::diagram_simulation::signalValue $portSignals($portTag)]
    }

    return x
}

proc ::svvs::diagram_simulation::valueColor {value} {
    set normalized [string tolower [string trim $value]]
    if {$normalized eq "x" || $normalized eq "z"} { return [::svvs::theme::color error] }
    set number [::svvs::diagram_simulation::integerValue $value]
    if {$number ne "" && $number != 0} { return [::svvs::theme::color success] }
    return #5f6873
}

proc ::svvs::diagram_simulation::redraw {} {
    variable active
    variable model
    variable portSignals
    if {!$active || $model eq ""} { return }
    set canvas $::svvs::canvas_blocks::canvas
    if {$canvas eq "" || ![winfo exists $canvas]} { return }
    $canvas delete simulation-overlay

    set hx [$canvas canvasx [::svvs::theme::scale 16]]
    set hy [$canvas canvasy [::svvs::theme::scale 16]]
    $canvas create rectangle $hx $hy \
        [expr {$hx + [::svvs::theme::scale 118]}] [expr {$hy + [::svvs::theme::scale 27]}] \
        -fill #244b3a -outline [::svvs::theme::color success] \
        -tags {simulation-overlay simulation-hud}
    $canvas create text [expr {$hx + [::svvs::theme::scale 59]}] \
        [expr {$hy + [::svvs::theme::scale 14]}] -text "SIMULATION ACTIVE" \
        -fill #dff4e6 -font [::svvs::theme::font "Segoe UI" 8 bold] \
        -tags {simulation-overlay simulation-hud}

    if {[dict exists $model signalBlocks]} {
        foreach item [dict get $model signalBlocks] {
            set value [::svvs::diagram_simulation::signalValue [dict get $item signal]]
            ::svvs::simulation_components::updateDisplay [dict get $item block] $value
        }
    }
    foreach portTag [array names portSignals] {
        set value [::svvs::diagram_simulation::signalValue $portSignals($portTag)]
        set color [::svvs::diagram_simulation::valueColor $value]
        foreach item [$canvas find withtag $portTag] {
            if {[lsearch -exact [$canvas gettags $item] port] >= 0} {
                $canvas itemconfigure $item -fill $color -outline white
            }
        }
    }
    foreach id [array names ::svvs::canvas_connections::connections] {
        set connection $::svvs::canvas_connections::connections($id)
        set value [::svvs::diagram_simulation::connectionValue $connection]
        if {$value eq ""} { continue }
        set color [::svvs::diagram_simulation::valueColor $value]
        foreach item [$canvas find withtag $id] {
            if {[lsearch -exact [$canvas gettags $item] connection] >= 0} {
                $canvas itemconfigure $item -fill $color
            }
        }
    }
    $canvas raise simulation-overlay
}

proc ::svvs::diagram_simulation::setSourceBlockValue {blockId value} {
    variable model
    if {$model eq ""} { return }
    foreach signal [dict get $model inputs] {
        if {[dict exists $signal sourceBlock] && [dict get $signal sourceBlock] eq $blockId} {
            ::svvs::simulator_view::setInputValue [dict get $signal name] $value
            return
        }
    }
}

proc ::svvs::diagram_simulation::drawBadge {record signal editable} {
    set canvas $::svvs::canvas_blocks::canvas
    set tag [dict get $record tag]
    set center [::svvs::canvas_blocks::portCenter $tag]
    if {[llength $center] != 2} { return }
    lassign $center px py
    set name [dict get $signal name]
    set value [::svvs::diagram_simulation::signalValue $name]
    set width [dict get $signal width]
    set color [::svvs::diagram_simulation::valueColor $value]
    set direction [dict get [dict get $record port] direction]
    set cx [expr {$direction eq "input" ? $px - [::svvs::theme::scale 30] : $px + [::svvs::theme::scale 30]}]
    set badgeTag "simulation-value:$name"
    set display [expr {$width > 1 ? "$value" : $value}]
    $canvas create rectangle [expr {$cx - [::svvs::theme::scale 22]}] \
        [expr {$py - [::svvs::theme::scale 11]}] \
        [expr {$cx + [::svvs::theme::scale 22]}] \
        [expr {$py + [::svvs::theme::scale 11]}] -fill [::svvs::theme::color panelAlt] \
        -outline $color -width [::svvs::theme::scale 2] -tags [list simulation-overlay $badgeTag]
    $canvas create text $cx $py -text $display -fill white \
        -font [::svvs::theme::font "Cascadia Mono" 9 bold] \
        -tags [list simulation-overlay $badgeTag]
    if {$editable} {
        set script [list ::svvs::diagram_simulation::editInput $name $width]
        append script "\nbreak"
        $canvas bind $badgeTag <Button-1> $script
    }
}

proc ::svvs::diagram_simulation::editInput {name width} {
    variable editSignal
    variable editValue
    set current [::svvs::diagram_simulation::signalValue $name]
    if {$width == 1} {
        set next [expr {$current eq "1" ? 0 : 1}]
        ::svvs::simulator_view::setInputValue $name $next
        return
    }
    set editSignal $name
    set editValue [expr {[string is integer -strict $current] ? $current : 0}]
    catch {destroy .simulationInput}
    toplevel .simulationInput
    wm title .simulationInput "Set input"
    wm transient .simulationInput .
    wm resizable .simulationInput 0 0
    .simulationInput configure -background [::svvs::theme::color panel]
    ttk::label .simulationInput.name -text "$name (${width} bits)" -style Panel.TLabel
    ttk::entry .simulationInput.value -textvariable ::svvs::diagram_simulation::editValue -width 18
    ttk::button .simulationInput.apply -text "Apply" -command ::svvs::diagram_simulation::commitInput
    grid .simulationInput.name -row 0 -column 0 -columnspan 2 -sticky w \
        -padx [::svvs::theme::scale 14] -pady [::svvs::theme::scaleList {14 8}]
    grid .simulationInput.value -row 1 -column 0 \
        -padx [::svvs::theme::scaleList {14 8}] -pady [::svvs::theme::scaleList {0 14}]
    grid .simulationInput.apply -row 1 -column 1 \
        -padx [::svvs::theme::scaleList {0 14}] -pady [::svvs::theme::scaleList {0 14}]
    bind .simulationInput.value <Return> {::svvs::diagram_simulation::commitInput}
    focus .simulationInput.value
    .simulationInput.value selection range 0 end
}

proc ::svvs::diagram_simulation::commitInput {} {
    variable editSignal
    variable editValue
    ::svvs::simulator_view::setInputValue $editSignal $editValue
    destroy .simulationInput
}
