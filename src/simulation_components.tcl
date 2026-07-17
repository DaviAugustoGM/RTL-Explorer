namespace eval ::svvs::simulation_components {
    variable editBlock ""
    variable editValue 0
    variable editFrequency 1.0
    variable editName ""
    variable mapBlock ""
    variable mapValue ""
    variable mapText ""
    variable mapTree ""
}

proc ::svvs::simulation_components::kind {module} {
    if {[dict exists $module simulationKind]} { return [dict get $module simulationKind] }
    switch -- [dict get $module name] {
        input_signal { return input }
        output_probe { return probe }
        clock_generator { return clock }
    }
    return ""
}

proc ::svvs::simulation_components::isVirtual {module} {
    return [expr {[::svvs::simulation_components::kind $module] ne ""}]
}

proc ::svvs::simulation_components::isBuiltin {module} {
    if {[dict exists $module builtin] && [dict get $module builtin]} { return 1 }
    return [expr {[dict get $module name] in {
        input_signal output_probe clock_generator reset_pulse constant
        and_gate or_gate mux2 register counter
    }}]
}

proc ::svvs::simulation_components::templateByKind {kind} {
    foreach module [::svvs::project_tree::builtinModules simulation] {
        if {[::svvs::simulation_components::kind $module] eq $kind} {
            return $module
        }
    }
    return ""
}

proc ::svvs::simulation_components::portConnectedToKind {portTag kind} {
    foreach id [array names ::svvs::canvas_connections::connections] {
        set conn $::svvs::canvas_connections::connections($id)
        set other ""
        if {[dict get $conn from] eq $portTag} {
            set other [dict get $conn to]
        } elseif {[dict get $conn to] eq $portTag} {
            set other [dict get $conn from]
        }
        if {$other eq "" || ![info exists ::svvs::canvas_blocks::tagToBlock($other)]} {
            continue
        }
        set blockId $::svvs::canvas_blocks::tagToBlock($other)
        if {![info exists ::svvs::canvas_blocks::blocks($blockId)]} {
            continue
        }
        set module [dict get $::svvs::canvas_blocks::blocks($blockId) module]
        if {[::svvs::simulation_components::kind $module] eq $kind} {
            return 1
        }
    }
    return 0
}

proc ::svvs::simulation_components::configuredSignalModule {kind portName width} {
    set module [::svvs::simulation_components::templateByKind $kind]
    if {$module eq ""} { return "" }
    dict set module simulationConfig bitWidth $width
    dict set module simulationConfig label $portName
    dict set module simulationConfig nameAssigned 1
    if {$kind eq "probe"} {
        dict set module simulationConfig base hex
    }
    set updatedPorts {}
    foreach port [dict get $module ports] {
        dict set port width $width
        lappend updatedPorts $port
    }
    dict set module ports $updatedPorts
    return $module
}

proc ::svvs::simulation_components::clockPortName {name width} {
    if {$width != 1} { return 0 }
    return [regexp -nocase {^(clk|clock|.*_clk|.*_clock)$} $name]
}

proc ::svvs::simulation_components::portConnectedToVirtualSource {portTag} {
    return [expr {
        [::svvs::simulation_components::portConnectedToKind $portTag input] ||
        [::svvs::simulation_components::portConnectedToKind $portTag clock]
    }]
}

proc ::svvs::simulation_components::autoIoForSelected {mode} {
    set blockId [::svvs::canvas_blocks::selectedBlockId]
    if {$blockId eq ""} {
        ::svvs::console::log "Selecione um modulo no diagrama antes de autoconectar entradas ou saidas." warn
        return 0
    }
    return [::svvs::simulation_components::autoIoForBlock $blockId $mode]
}

proc ::svvs::simulation_components::autoIoPositionRows {items minGap} {
    set sorted [lsort -real -index 0 $items]
    set rows {}
    if {[llength $sorted] == 0} {
        return $rows
    }
    foreach item $sorted {
        set desiredY [lindex $item 0]
        set y $desiredY
        if {[llength $rows] > 0} {
            set previous [lindex [lindex $rows end] 0]
            set y [expr {max($desiredY, $previous + $minGap)}]
        }
        lappend rows [list $y [lrange $item 1 end]]
    }

    set desiredCenter [expr {([lindex [lindex $sorted 0] 0] + [lindex [lindex $sorted end] 0]) / 2.0}]
    set packedCenter [expr {([lindex [lindex $rows 0] 0] + [lindex [lindex $rows end] 0]) / 2.0}]
    set shift [expr {$desiredCenter - $packedCenter}]
    if {$shift != 0} {
        set shifted {}
        foreach row $rows {
            lappend shifted [list [expr {[lindex $row 0] + $shift}] [lindex $row 1]]
        }
        set rows $shifted
    }
    return $rows
}

proc ::svvs::simulation_components::autoIoForBlock {blockId mode} {
    if {![info exists ::svvs::canvas_blocks::blocks($blockId)]} {
        return 0
    }
    set targetBlock $::svvs::canvas_blocks::blocks($blockId)
    set targetModule [dict get $targetBlock module]
    if {[::svvs::simulation_components::isVirtual $targetModule]} {
        ::svvs::console::log "Escolha um modulo Verilog/SystemVerilog, nao um bloco de sinal." warn
        return 0
    }

    set x [dict get $targetBlock x]
    set width [dict get $targetBlock width]
    set zoom $::svvs::canvas_blocks::zoom
    set inputX [expr {$x - ([::svvs::theme::scale 92] * $zoom)}]
    set outputX [expr {$x + $width + ([::svvs::theme::scale 28] * $zoom)}]
    set signalHeight [expr {[::svvs::theme::scale 44] * $zoom}]
    set blockYOffset [expr {$signalHeight / 2.0}]
    set rowGap [expr {$signalHeight + ([::svvs::theme::scale 20] * $zoom)}]
    set inputItems {}
    set outputItems {}
    set inputCount 0
    set clockCount 0
    set outputCount 0
    set created 0

    foreach port [dict get $targetModule ports] {
        set direction [dict get $port direction]
        set portName [dict get $port name]
        set portWidth [dict get $port width]
        set portTag "port:$blockId:$portName"
        if {![info exists ::svvs::canvas_blocks::tagToPort($portTag)]} {
            continue
        }
        set center [::svvs::canvas_blocks::portCenter $portTag]
        set portY [lindex $center 1]

        if {$direction eq "input" && $mode in {inputs both}} {
            if {[::svvs::simulation_components::portConnectedToVirtualSource $portTag]} {
                continue
            }
            if {[::svvs::simulation_components::clockPortName $portName $portWidth]} {
                set sourceKind clock
            } else {
                set sourceKind input
            }
            set module [::svvs::simulation_components::configuredSignalModule \
                $sourceKind $portName $portWidth]
            if {$module eq ""} { continue }
            lappend inputItems [list $portY $module $sourceKind $portTag $portWidth]
        } elseif {$direction eq "output" && $mode in {outputs both}} {
            if {[::svvs::simulation_components::portConnectedToKind $portTag probe]} {
                continue
            }
            set module [::svvs::simulation_components::configuredSignalModule probe $portName $portWidth]
            if {$module eq ""} { continue }
            lappend outputItems [list $portY $module probe $portTag $portWidth]
        }
    }

    foreach row [::svvs::simulation_components::autoIoPositionRows $inputItems $rowGap] {
        set signalY [expr {[lindex $row 0] - $blockYOffset}]
        lassign [lindex $row 1] module sourceKind portTag portWidth
        set module [::svvs::canvas_blocks::nextInstanceModule $module]
        set newId [::svvs::canvas_blocks::drawBlock $module $inputX $signalY]
        if {$sourceKind eq "clock"} {
            ::svvs::canvas_connections::drawConnection "port:$newId:clk" $portTag $portWidth
            incr clockCount
        } else {
            ::svvs::canvas_connections::drawConnection "port:$newId:out" $portTag $portWidth
            incr inputCount
        }
        incr created
    }

    foreach row [::svvs::simulation_components::autoIoPositionRows $outputItems $rowGap] {
        set signalY [expr {[lindex $row 0] - $blockYOffset}]
        lassign [lindex $row 1] module sourceKind portTag portWidth
        set module [::svvs::canvas_blocks::nextInstanceModule $module]
        set newId [::svvs::canvas_blocks::drawBlock $module $outputX $signalY]
        ::svvs::canvas_connections::drawConnection $portTag "port:$newId:in" $portWidth
        incr outputCount
        incr created
    }

    ::svvs::canvas_connections::refreshAll
    if {$::svvs::diagram_simulation::active} { ::svvs::diagram_simulation::redraw }
    if {$created == 0} {
        ::svvs::console::log "Nenhum bloco de I/O novo foi criado. As portas podem ja estar conectadas." warn
    } else {
        ::svvs::console::log \
            "Auto I/O: $inputCount entrada(s), $clockCount clock(s) e $outputCount saida(s) criadas." ok
    }
    return $created
}

proc ::svvs::simulation_components::config {module key default} {
    if {[dict exists $module simulationConfig $key]} {
        return [dict get $module simulationConfig $key]
    }
    return $default
}

proc ::svvs::simulation_components::blockConnected {portTag} {
    foreach id [array names ::svvs::canvas_connections::connections] {
        set connection $::svvs::canvas_connections::connections($id)
        if {[dict get $connection from] eq $portTag || [dict get $connection to] eq $portTag} {
            return 1
        }
    }
    return 0
}

proc ::svvs::simulation_components::adaptConnection {fromTag toTag} {
    set fromInfo [::svvs::canvas_blocks::portInfo $fromTag]
    set toInfo [::svvs::canvas_blocks::portInfo $toTag]
    if {$fromInfo eq "" || $toInfo eq ""} { return 1 }
    set fromKind [::svvs::simulation_components::kind [dict get $fromInfo module]]
    set toKind [::svvs::simulation_components::kind [dict get $toInfo module]]
    set fromWidth [dict get [dict get $fromInfo port] width]
    set toWidth [dict get [dict get $toInfo port] width]

    if {$fromKind eq "clock" || $toKind eq "clock"} {
        set otherWidth [expr {$fromKind eq "clock" ? $toWidth : $fromWidth}]
        if {$otherWidth != 1} {
            ::svvs::console::log "Clock so pode ser conectado a uma porta de 1 bit." warn
            return 0
        }
    }
    if {$fromKind in {input probe} && $fromWidth != $toWidth} {
        if {[::svvs::simulation_components::blockConnected $fromTag]} {
            ::svvs::console::log "O bloco de sinal ja esta ligado a uma rede de $fromWidth bits." warn
            return 0
        }
        ::svvs::simulation_components::setPortWidth $fromTag $toWidth
    }
    if {$toKind in {input probe} && $toWidth != $fromWidth} {
        if {[::svvs::simulation_components::blockConnected $toTag]} {
            ::svvs::console::log "O bloco de sinal ja esta ligado a uma rede de $toWidth bits." warn
            return 0
        }
        ::svvs::simulation_components::setPortWidth $toTag $fromWidth
    }
    ::svvs::simulation_components::assignConnectionNames $fromTag $toTag
    return 1
}

proc ::svvs::simulation_components::assignConnectionNames {fromTag toTag} {
    set fromInfo [::svvs::canvas_blocks::portInfo $fromTag]
    set toInfo [::svvs::canvas_blocks::portInfo $toTag]
    if {$fromInfo eq "" || $toInfo eq ""} { return }
    set fromKind [::svvs::simulation_components::kind [dict get $fromInfo module]]
    set toKind [::svvs::simulation_components::kind [dict get $toInfo module]]
    if {$fromKind ne "" && $toKind eq ""} {
        ::svvs::simulation_components::assignAutomaticName \
            $fromTag [dict get [dict get $toInfo port] name]
    }
    if {$toKind ne "" && $fromKind eq ""} {
        ::svvs::simulation_components::assignAutomaticName \
            $toTag [dict get [dict get $fromInfo port] name]
    }
}

proc ::svvs::simulation_components::assignAutomaticName {portTag name} {
    if {![regexp {^port:([^:]+):} $portTag -> id]} { return }
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return }
    set block $::svvs::canvas_blocks::blocks($id)
    set module [dict get $block module]
    if {[::svvs::simulation_components::config $module nameAssigned 0]} { return }
    dict set module simulationConfig label $name
    dict set module simulationConfig nameAssigned 1
    dict set block module $module
    set ::svvs::canvas_blocks::blocks($id) $block
    ::svvs::simulation_components::updateNameDisplay $id
}

proc ::svvs::simulation_components::displayName {module} {
    set label [::svvs::simulation_components::config $module label ""]
    if {$label ne ""} { return $label }
    return [dict get $module instance]
}

proc ::svvs::simulation_components::clipDisplayText {text maxChars} {
    set maxChars [expr {int($maxChars)}]
    set length [string length $text]
    if {$length <= $maxChars} { return $text }
    if {$maxChars <= 0} { return "" }
    if {$maxChars <= 3} {
        return [string range $text 0 [expr {$maxChars - 1}]]
    }

    if {[regexp -nocase {^(0b|0x)} $text -> prefix] && $maxChars >= 7} {
        set suffixCount [expr {$maxChars - [string length $prefix] - 3}]
        if {$suffixCount < 1} {
            return "${prefix}..."
        }
        return "${prefix}...[string range $text end-[expr {$suffixCount - 1}] end]"
    }

    return "[string range $text 0 [expr {$maxChars - 4}]]..."
}

proc ::svvs::simulation_components::componentFontInfo {id text} {
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} {
        return [list $text [::svvs::theme::scale 10]]
    }

    set block $::svvs::canvas_blocks::blocks($id)
    set width [dict get $block width]
    set height [dict get $block height]
    set zoom $::svvs::canvas_blocks::zoom
    set margin [expr {max([::svvs::theme::scale 8], [::svvs::theme::scale 10] * $zoom)}]
    set available [expr {max([::svvs::theme::scale 10], $width - $margin)}]
    set minSize [::svvs::theme::scale 5]
    set maxSize [::svvs::theme::scale 24]
    set target [expr {int(round([::svvs::theme::scale 12] * $zoom))}]
    set heightLimit [expr {int(max($minSize, $height * 0.48))}]
    set fontSize [expr {min($maxSize, max($minSize, min($target, $heightLimit)))}]
    set maxChars [expr {int($available / max(1.0, $fontSize * 0.62))}]
    set clipped [::svvs::simulation_components::clipDisplayText $text $maxChars]

    set length [string length $clipped]
    if {$length > 0} {
        set fitSize [expr {int($available / max(1.0, $length * 0.62))}]
        set fontSize [expr {min($fontSize, max($minSize, $fitSize))}]
    }
    return [list $clipped $fontSize]
}

proc ::svvs::simulation_components::componentLabelFontSize {} {
    set zoom $::svvs::canvas_blocks::zoom
    set size [expr {int(round([::svvs::theme::scale 8] * $zoom))}]
    return [expr {max([::svvs::theme::scale 5], min([::svvs::theme::scale 12], $size))}]
}

proc ::svvs::simulation_components::setPortWidth {portTag width} {
    if {![regexp {^port:([^:]+):(.+)$} $portTag -> id portName]} { return }
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return }
    set block $::svvs::canvas_blocks::blocks($id)
    set module [dict get $block module]
    set updated {}
    foreach port [dict get $module ports] {
        if {[dict get $port name] eq $portName} { dict set port width $width }
        lappend updated $port
    }
    dict set module ports $updated
    dict set module simulationConfig bitWidth $width
    dict set block module $module
    set ::svvs::canvas_blocks::blocks($id) $block
    foreach port $updated {
        if {[dict get $port name] eq $portName} {
            set ::svvs::canvas_blocks::tagToPort($portTag) $port
        }
    }
    ::svvs::canvas_blocks::layoutBlock $id
    ::svvs::simulation_components::updateDisplay $id
}

proc ::svvs::simulation_components::decorateBlock {id} {
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return }
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    if {![::svvs::simulation_components::isVirtual $module]} { return }
    set kind [::svvs::simulation_components::kind $module]
    set canvas $::svvs::canvas_blocks::canvas
    set tag "block:$id"
    foreach item [$canvas find withtag $tag] {
        set tags [$canvas gettags $item]
        if {[lsearch -exact $tags resize-handle] >= 0 && $kind in {input probe clock}} {
            $canvas dtag $item simulation-hidden
            $canvas itemconfigure $item -state normal
        } elseif {[lsearch -exact $tags block-header] >= 0 ||
            [lsearch -exact $tags block-title] >= 0 ||
            [lsearch -exact $tags port-label] >= 0 ||
            [lsearch -exact $tags resize-handle] >= 0} {
            $canvas addtag simulation-hidden withtag $item
            $canvas itemconfigure $item -state hidden
        }
    }
    if {[llength [$canvas find withtag "simulation-component:$id"]] == 0} {
        $canvas create text 0 0 -text "0" -fill [::svvs::theme::color accentHover] \
            -font [::svvs::theme::font "Cascadia Mono" 12 bold] \
            -tags [list $tag "simulation-component:$id" simulation-component]
        set script [list ::svvs::simulation_components::activateBlock $id]
        append script "\nbreak"
        $canvas bind "simulation-component:$id" <Button-1> $script
        $canvas bind "simulation-component:$id" <Double-1> {break}
    }
    if {[llength [$canvas find withtag "simulation-component-label:$id"]] == 0} {
        $canvas create text 0 0 -text "" -anchor s \
            -fill [::svvs::theme::color muted] -font [::svvs::theme::font "Segoe UI" 8] \
            -tags [list $tag "simulation-component-label:$id" simulation-component-label]
    }
    ::svvs::simulation_components::layoutDecoration $id
    ::svvs::simulation_components::updateDisplay $id
    ::svvs::simulation_components::updateNameDisplay $id
}

proc ::svvs::simulation_components::layoutDecoration {id} {
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return }
    set block $::svvs::canvas_blocks::blocks($id)
    if {![::svvs::simulation_components::isVirtual [dict get $block module]]} { return }
    set x [dict get $block x]
    set y [dict get $block y]
    set width [dict get $block width]
    set height [dict get $block height]
    set zoom $::svvs::canvas_blocks::zoom
    $::svvs::canvas_blocks::canvas coords "simulation-component:$id" \
        [expr {$x + $width / 2.0}] [expr {$y + $height / 2.0}]
    $::svvs::canvas_blocks::canvas coords "simulation-component-label:$id" \
        [expr {$x + $width / 2.0}] [expr {$y - ([::svvs::theme::scale 5] * $zoom)}]
}

proc ::svvs::simulation_components::updateNameDisplay {id} {
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return }
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set label [::svvs::simulation_components::config $module label ""]
    set canvas $::svvs::canvas_blocks::canvas
    if {$canvas ne "" && [winfo exists $canvas]} {
        $canvas itemconfigure "simulation-component-label:$id" -text $label \
            -font [list {Segoe UI} [::svvs::simulation_components::componentLabelFontSize]] \
            -state [expr {$label eq "" ? "hidden" : "normal"}]
    }
}

proc ::svvs::simulation_components::formatValue {value width base} {
    if {![string is integer -strict $value]} { return [string toupper $value] }
    set maxValue [expr {(1 << $width) - 1}]
    set value [expr {$value & $maxValue}]
    switch -- $base {
        bin { return "0b[format %0${width}b $value]" }
        hex {
            set digits [expr {int(ceil($width / 4.0))}]
            return "0x[format %0${digits}X $value]"
        }
        default { return $value }
    }
}

proc ::svvs::simulation_components::formatMappedValue {value width base {valueMap {}}} {
    if {[string is integer -strict $value]} {
        set key [expr {$value & ((1 << $width) - 1)}]
        if {[dict exists $valueMap $key] && [dict get $valueMap $key] ne ""} {
            return [dict get $valueMap $key]
        }
    }
    return [::svvs::simulation_components::formatValue $value $width $base]
}

proc ::svvs::simulation_components::parseMappedValue {text} {
    set text [string trim $text]
    if {[regexp -nocase {^0b} $text]} {
        return [::svvs::simulation_components::parseValue $text bin]
    }
    if {[regexp -nocase {^0x} $text]} {
        return [::svvs::simulation_components::parseValue $text hex]
    }
    return [::svvs::simulation_components::parseValue $text dec]
}

proc ::svvs::simulation_components::updateDisplay {id {liveValue ""}} {
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return }
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set kind [::svvs::simulation_components::kind $module]
    if {$kind eq ""} { return }
    set width [::svvs::simulation_components::config $module bitWidth 1]
    set base [::svvs::simulation_components::config $module base bin]
    if {$liveValue eq ""} {
        if {$kind eq "clock"} {
            set frequency [::svvs::simulation_components::config $module frequency 1.0]
            set display "${frequency} Hz"
        } elseif {$kind eq "probe"} {
            set display "X"
        } else {
            set valueMap [::svvs::simulation_components::config $module valueMap {}]
            set display [::svvs::simulation_components::formatMappedValue \
                [::svvs::simulation_components::config $module value 0] $width $base $valueMap]
        }
    } else {
        set valueMap [::svvs::simulation_components::config $module valueMap {}]
        set display [::svvs::simulation_components::formatMappedValue \
            $liveValue $width $base $valueMap]
    }
    set canvas $::svvs::canvas_blocks::canvas
    if {$canvas ne "" && [winfo exists $canvas]} {
        lassign [::svvs::simulation_components::componentFontInfo $id $display] visible fontSize
        $canvas itemconfigure "simulation-component:$id" -text $visible \
            -font [list {Cascadia Mono} $fontSize bold]
    }
}

proc ::svvs::simulation_components::refreshAllDisplays {} {
    foreach id [array names ::svvs::canvas_blocks::blocks] {
        set module [dict get $::svvs::canvas_blocks::blocks($id) module]
        if {![::svvs::simulation_components::isVirtual $module]} {
            continue
        }
        ::svvs::simulation_components::layoutDecoration $id
        ::svvs::simulation_components::updateDisplay $id
        ::svvs::simulation_components::updateNameDisplay $id
    }
}

proc ::svvs::simulation_components::rightClick {rootX rootY x y} {
    set blockTag [::svvs::canvas_blocks::tagAt $x $y "block:"]
    if {$blockTag eq ""} { return 0 }
    set id [::svvs::canvas_blocks::blockIdFromTag $blockTag]
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return 0 }
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set kind [::svvs::simulation_components::kind $module]
    if {$kind eq ""} { return 0 }
    ::svvs::simulation_components::showMenu $id $rootX $rootY
    return 1
}

proc ::svvs::simulation_components::showMenu {id rootX rootY {post 1}} {
    catch {destroy .signalBlockMenu}
    menu .signalBlockMenu -tearoff 0 -background [::svvs::theme::color panel] \
        -foreground [::svvs::theme::color text] -activebackground [::svvs::theme::color selected] \
        -activeforeground white
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set kind [::svvs::simulation_components::kind $module]
    .signalBlockMenu add command -label "Rename..." \
        -command [list ::svvs::simulation_components::renameDialog $id]
    .signalBlockMenu add separator
    if {$kind eq "input"} {
        .signalBlockMenu add command -label "Set value..." \
            -command [list ::svvs::simulation_components::editValueDialog $id]
        menu .signalBlockMenu.clickAction -tearoff 0
        .signalBlockMenu.clickAction add command -label "Edit value" \
            -command [list ::svvs::simulation_components::setClickAction $id edit]
        .signalBlockMenu.clickAction add command -label "Increment" \
            -command [list ::svvs::simulation_components::setClickAction $id increment]
        .signalBlockMenu.clickAction add command -label "Slider" \
            -command [list ::svvs::simulation_components::setClickAction $id slider]
        .signalBlockMenu.clickAction add command -label "Momentary pulse" \
            -command [list ::svvs::simulation_components::setClickAction $id pulse]
        .signalBlockMenu add cascade -label "Click action" -menu .signalBlockMenu.clickAction
    }
    if {$kind in {input probe}} {
        .signalBlockMenu add command -label "Value labels..." \
            -command [list ::svvs::simulation_components::valueMapDialog $id]
        .signalBlockMenu add command -label "Clear value labels" \
            -command [list ::svvs::simulation_components::clearValueMapForBlock $id]
        menu .signalBlockMenu.valueFiles -tearoff 0
        .signalBlockMenu.valueFiles add command -label "Load for this block..." \
            -command [list ::svvs::simulation_components::importValueMapForBlockDialog $id]
        .signalBlockMenu.valueFiles add command -label "Save this block..." \
            -command [list ::svvs::simulation_components::exportValueMapForBlockDialog $id]
        .signalBlockMenu add cascade -label "Value label file" -menu .signalBlockMenu.valueFiles
    }
    if {$kind eq "clock"} {
        .signalBlockMenu add command -label "Set frequency..." \
            -command [list ::svvs::simulation_components::frequencyDialog $id]
        menu .signalBlockMenu.frequency -tearoff 0
        foreach frequency {0.5 1 2 5 10 20} {
            .signalBlockMenu.frequency add command -label "$frequency Hz" \
                -command [list ::svvs::simulation_components::setFrequency $id $frequency]
        }
        .signalBlockMenu add cascade -label "Frequency" -menu .signalBlockMenu.frequency
    } else {
        menu .signalBlockMenu.base -tearoff 0
        foreach {label base} {Binary bin Decimal dec Hexadecimal hex} {
            .signalBlockMenu.base add command -label $label \
                -command [list ::svvs::simulation_components::setBase $id $base]
        }
        .signalBlockMenu add cascade -label "Number format" -menu .signalBlockMenu.base
    }
    .signalBlockMenu add separator
    set trace [::svvs::simulation_components::config $module trace 1]
    .signalBlockMenu add command -label [expr {$trace ? "Hide waveform" : "Show waveform"}] \
        -command [list ::svvs::simulation_components::toggleTrace $id]
    if {$post} { tk_popup .signalBlockMenu $rootX $rootY }
}

proc ::svvs::simulation_components::setConfig {id key value} {
    set block $::svvs::canvas_blocks::blocks($id)
    set module [dict get $block module]
    dict set module simulationConfig $key $value
    dict set block module $module
    set ::svvs::canvas_blocks::blocks($id) $block
    ::svvs::simulation_components::updateDisplay $id
    ::svvs::simulation_components::updateNameDisplay $id
    ::svvs::canvas_blocks::showBlockProperties "block:$id"
    if {$::svvs::diagram_simulation::active} {
        ::svvs::simulator_view::refreshComponentConfiguration [expr {$key eq "frequency"}]
    }
}

proc ::svvs::simulation_components::renameDialog {id} {
    variable editBlock
    variable editName
    set editBlock $id
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set editName [::svvs::simulation_components::config $module label ""]
    ::svvs::simulation_components::showEditor "Signal name" editName commitName
}

proc ::svvs::simulation_components::commitName {} {
    variable editBlock
    variable editName
    set editName [string trim $editName]
    if {$editName eq ""} {
        ::svvs::console::log "O nome do sinal nao pode ficar vazio." warn
        return
    }
    ::svvs::simulation_components::setConfig $editBlock label $editName
    ::svvs::simulation_components::setConfig $editBlock nameAssigned 1
    destroy .componentEditor
}

proc ::svvs::simulation_components::setBase {id base} {
    ::svvs::simulation_components::setConfig $id base $base
    ::svvs::simulation_components::clearValueMapForBlock $id 1
    ::svvs::console::log "Formato numerico alterado; mapeamento do bloco removido."
}

proc ::svvs::simulation_components::setClickAction {id action} {
    ::svvs::simulation_components::setConfig $id clickAction $action
}

proc ::svvs::simulation_components::valueMapDialog {id} {
    variable mapBlock
    variable mapValue
    variable mapText
    variable mapTree
    set mapBlock $id
    set mapValue ""
    set mapText ""
    catch {destroy .valueMapEditor}
    toplevel .valueMapEditor
    wm title .valueMapEditor "Value labels"
    wm transient .valueMapEditor .
    wm minsize .valueMapEditor 430 300

    ttk::label .valueMapEditor.help \
        -text "Map a binary, hexadecimal, or decimal value to a label."
    set mapTree [ttk::treeview .valueMapEditor.list -columns {value text} \
        -show headings -height 8 -selectmode browse]
    $mapTree heading value -text "Value"
    $mapTree heading text -text "Displayed text"
    $mapTree column value -width 110 -stretch 0
    $mapTree column text -width 240 -stretch 1
    ttk::scrollbar .valueMapEditor.scroll -orient vertical -command "$mapTree yview"
    $mapTree configure -yscrollcommand ".valueMapEditor.scroll set"

    set form [ttk::frame .valueMapEditor.form]
    ttk::label $form.valueLabel -text "Value"
    ttk::entry $form.value -textvariable ::svvs::simulation_components::mapValue -width 14
    ttk::label $form.textLabel -text "Text"
    ttk::entry $form.text -textvariable ::svvs::simulation_components::mapText -width 24
    ttk::button $form.add -text "Add / Update" \
        -command ::svvs::simulation_components::commitValueMapEntry
    pack $form.valueLabel $form.value $form.textLabel $form.text $form.add \
        -side left -padx {0 6}

    set actions [ttk::frame .valueMapEditor.actions]
    ttk::button $actions.remove -text "Remove selected" \
        -command ::svvs::simulation_components::removeValueMapEntry
    ttk::button $actions.close -text "Done" -command {destroy .valueMapEditor}
    pack $actions.remove -side left
    pack $actions.close -side right

    grid .valueMapEditor.help -row 0 -column 0 -columnspan 2 -sticky w -padx 14 -pady {14 8}
    grid $mapTree -row 1 -column 0 -sticky nsew -padx {14 0}
    grid .valueMapEditor.scroll -row 1 -column 1 -sticky ns -padx {0 14}
    grid $form -row 2 -column 0 -columnspan 2 -sticky ew -padx 14 -pady 10
    grid $actions -row 3 -column 0 -columnspan 2 -sticky ew -padx 14 -pady {0 14}
    grid rowconfigure .valueMapEditor 1 -weight 1
    grid columnconfigure .valueMapEditor 0 -weight 1
    bind $mapTree <<TreeviewSelect>> {::svvs::simulation_components::selectValueMapEntry}
    bind $form.value <Return> {focus .valueMapEditor.form.text}
    bind $form.text <Return> {::svvs::simulation_components::commitValueMapEntry}
    ::svvs::simulation_components::refreshValueMapEditor
    focus $form.value
}

proc ::svvs::simulation_components::refreshValueMapEditor {} {
    variable mapBlock
    variable mapTree
    if {$mapTree eq "" || ![winfo exists $mapTree] ||
        ![info exists ::svvs::canvas_blocks::blocks($mapBlock)]} { return }
    $mapTree delete [$mapTree children {}]
    set module [dict get $::svvs::canvas_blocks::blocks($mapBlock) module]
    set valueMap [::svvs::simulation_components::config $module valueMap {}]
    foreach value [lsort -integer [dict keys $valueMap]] {
        $mapTree insert {} end -id "value:$value" -values [list $value [dict get $valueMap $value]]
    }
}

proc ::svvs::simulation_components::selectValueMapEntry {} {
    variable mapTree
    variable mapValue
    variable mapText
    set selection [$mapTree selection]
    if {[llength $selection] == 0} { return }
    lassign [$mapTree item [lindex $selection 0] -values] mapValue mapText
}

proc ::svvs::simulation_components::commitValueMapEntry {} {
    variable mapBlock
    variable mapValue
    variable mapText
    set parsed [::svvs::simulation_components::parseMappedValue $mapValue]
    set text [string trim $mapText]
    if {![lindex $parsed 0] || $text eq ""} {
        ::svvs::console::log "Informe um valor valido e um texto nao vazio." warn
        return
    }
    set value [lindex $parsed 1]
    set module [dict get $::svvs::canvas_blocks::blocks($mapBlock) module]
    set width [::svvs::simulation_components::config $module bitWidth 1]
    if {$value < 0 || $value >= (1 << $width)} {
        ::svvs::console::log "O valor nao cabe em $width bits." warn
        return
    }
    set valueMap [::svvs::simulation_components::config $module valueMap {}]
    dict set valueMap $value $text
    ::svvs::simulation_components::setConfig $mapBlock valueMap $valueMap
    set mapValue ""
    set mapText ""
    ::svvs::simulation_components::refreshValueMapEditor
    focus .valueMapEditor.form.value
}

proc ::svvs::simulation_components::removeValueMapEntry {} {
    variable mapBlock
    variable mapTree
    set selection [$mapTree selection]
    if {[llength $selection] == 0} { return }
    set value [lindex [$mapTree item [lindex $selection 0] -values] 0]
    set module [dict get $::svvs::canvas_blocks::blocks($mapBlock) module]
    set valueMap [::svvs::simulation_components::config $module valueMap {}]
    if {[dict exists $valueMap $value]} { dict unset valueMap $value }
    ::svvs::simulation_components::setConfig $mapBlock valueMap $valueMap
    ::svvs::simulation_components::refreshValueMapEditor
}

proc ::svvs::simulation_components::clearValueMapForBlock {id {silent 0}} {
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return 0 }
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    if {[::svvs::simulation_components::kind $module] ni {input probe}} {
        return 0
    }
    set valueMap [::svvs::simulation_components::config $module valueMap {}]
    if {[dict size $valueMap] == 0} {
        if {!$silent} {
            ::svvs::console::log "Este bloco nao possui mapeamento de valores." warn
        }
        return 0
    }
    ::svvs::simulation_components::setConfig $id valueMap {}
    if {[winfo exists .valueMapEditor]} {
        ::svvs::simulation_components::refreshValueMapEditor
    }
    if {!$silent} {
        ::svvs::console::log "Mapeamento de valores removido do bloco." ok
    }
    return 1
}

proc ::svvs::simulation_components::clearAllValueMaps {} {
    set count 0
    foreach id [lsort [array names ::svvs::canvas_blocks::blocks]] {
        if {[::svvs::simulation_components::clearValueMapForBlock $id 1]} {
            incr count
        }
    }
    if {$count == 0} {
        ::svvs::console::log "Nenhum mapeamento de valores para remover." warn
    } else {
        ::svvs::console::log "Mapeamentos removidos de $count bloco(s)." ok
    }
    if {[winfo exists .valueMapEditor]} {
        ::svvs::simulation_components::refreshValueMapEditor
    }
    return $count
}

proc ::svvs::simulation_components::blockMapKey {id} {
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return "" }
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set label [::svvs::simulation_components::config $module label ""]
    if {$label ne ""} { return $label }
    return [dict get $module instance]
}

proc ::svvs::simulation_components::parseValueMapFile {path} {
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    set text [read $fh]
    close $fh

    set maps {}
    set current default
    foreach rawLine [split $text "\n"] {
        set line [string trim $rawLine]
        if {$line eq "" || [string match "#*" $line] || [string match "//*" $line]} {
            continue
        }
        if {[regexp {^\[([^\]]+)\]$} $line -> section]} {
            set current [string trim $section]
            continue
        }
        if {[regexp {^["']?([A-Za-z_][A-Za-z0-9_.$]*)["']?\s*[:=]\s*\x7b} $line -> section]} {
            set current [string trim $section]
            continue
        }
        if {[string index $line 0] eq [format %c 125]} {
            set current default
            continue
        }

        set signal ""
        set value ""
        set label ""
        if {[regexp {^([^,;=]+)[,;]\s*([^,;=]+)[,;]\s*(.+)$} $line -> signal value label]} {
            set signal [string trim $signal]
        } elseif {[regexp {^([^=:]+)\s*[:=]\s*(.+)$} $line -> value label]} {
            set signal $current
        } elseif {[regexp {"([^"]+)"\s*:\s*"([^"]+)"} $line -> value label]} {
            set signal $current
        } else {
            continue
        }
        set parsed [::svvs::simulation_components::parseMappedValue $value]
        set label [string trim $label]
        regsub {,$} $label "" label
        set label [string trim $label {"' }]
        if {![lindex $parsed 0] || $label eq ""} {
            continue
        }
        dict set maps $signal [lindex $parsed 1] $label
    }
    return $maps
}

proc ::svvs::simulation_components::serializeValueMaps {maps} {
    set lines [list "# RTL Explorer value maps" "# Use sections by signal name: \[signal_name\]" ""]
    foreach signal [lsort [dict keys $maps]] {
        lappend lines "\[$signal\]"
        set valueMap [dict get $maps $signal]
        foreach value [lsort -integer [dict keys $valueMap]] {
            lappend lines "$value = [dict get $valueMap $value]"
        }
        lappend lines ""
    }
    return [join $lines "\n"]
}

proc ::svvs::simulation_components::signalValueMaps {} {
    set maps {}
    foreach id [lsort [array names ::svvs::canvas_blocks::blocks]] {
        set module [dict get $::svvs::canvas_blocks::blocks($id) module]
        if {[::svvs::simulation_components::kind $module] ni {input probe}} {
            continue
        }
        set valueMap [::svvs::simulation_components::config $module valueMap {}]
        if {[dict size $valueMap] == 0} {
            continue
        }
        dict set maps [::svvs::simulation_components::blockMapKey $id] $valueMap
    }
    return $maps
}

proc ::svvs::simulation_components::applyValueMaps {maps {targetBlock ""}} {
    set applied 0
    foreach id [lsort [array names ::svvs::canvas_blocks::blocks]] {
        if {$targetBlock ne "" && $id ne $targetBlock} {
            continue
        }
        set module [dict get $::svvs::canvas_blocks::blocks($id) module]
        if {[::svvs::simulation_components::kind $module] ni {input probe}} {
            continue
        }
        set key [::svvs::simulation_components::blockMapKey $id]
        set map ""
        if {[dict exists $maps $key]} {
            set map [dict get $maps $key]
        } elseif {[dict exists $maps default]} {
            set map [dict get $maps default]
        }
        if {$map eq ""} {
            continue
        }
        ::svvs::simulation_components::setConfig $id valueMap $map
        incr applied
    }
    return $applied
}

proc ::svvs::simulation_components::importValueMapsDialog {} {
    set path [tk_getOpenFile \
        -title "Import signal value maps" \
        -filetypes {
            {"Value map files" {.txt .map .py}}
            {"Text files" {.txt}}
            {"Python files" {.py}}
            {"All files" {*}}
        }]
    if {$path eq ""} { return }
    ::svvs::simulation_components::importValueMapsFrom $path
}

proc ::svvs::simulation_components::importValueMapsFrom {path {targetBlock ""}} {
    if {[catch {set maps [::svvs::simulation_components::parseValueMapFile $path]} err]} {
        ::svvs::console::log "Erro ao ler mapas de valores: $err" error
        return 0
    }
    set applied [::svvs::simulation_components::applyValueMaps $maps $targetBlock]
    if {$applied == 0} {
        ::svvs::console::log "Nenhum mapa de valor combinou com os blocos de sinal atuais." warn
    } else {
        ::svvs::console::log "Mapas de valores aplicados em $applied bloco(s)." ok
    }
    return $applied
}

proc ::svvs::simulation_components::exportValueMapsDialog {} {
    set path [tk_getSaveFile \
        -title "Export signal value maps" \
        -defaultextension ".txt" \
        -filetypes {
            {"Value map files" {.txt .map}}
            {"Python files" {.py}}
            {"All files" {*}}
        }]
    if {$path eq ""} { return }
    ::svvs::simulation_components::exportValueMapsTo $path
}

proc ::svvs::simulation_components::exportValueMapsTo {path {targetBlock ""}} {
    if {$targetBlock eq ""} {
        set maps [::svvs::simulation_components::signalValueMaps]
    } else {
        if {![info exists ::svvs::canvas_blocks::blocks($targetBlock)]} { return 0 }
        set module [dict get $::svvs::canvas_blocks::blocks($targetBlock) module]
        set maps [dict create [::svvs::simulation_components::blockMapKey $targetBlock] \
            [::svvs::simulation_components::config $module valueMap {}]]
    }
    if {[dict size $maps] == 0} {
        ::svvs::console::log "Nenhum mapa de valor para salvar." warn
        return 0
    }
    if {[catch {
        set fh [open $path w]
        fconfigure $fh -encoding utf-8 -translation lf
        puts $fh [::svvs::simulation_components::serializeValueMaps $maps]
        close $fh
    } err]} {
        catch {close $fh}
        ::svvs::console::log "Erro ao salvar mapas de valores: $err" error
        return 0
    }
    ::svvs::console::log "Mapas de valores salvos: $path" ok
    return 1
}

proc ::svvs::simulation_components::importValueMapForBlockDialog {id} {
    set path [tk_getOpenFile \
        -title "Load value labels for this block" \
        -filetypes {
            {"Value map files" {.txt .map .py}}
            {"All files" {*}}
        }]
    if {$path eq ""} { return }
    ::svvs::simulation_components::importValueMapsFrom $path $id
}

proc ::svvs::simulation_components::exportValueMapForBlockDialog {id} {
    set path [tk_getSaveFile \
        -title "Save value labels for this block" \
        -defaultextension ".txt" \
        -filetypes {
            {"Value map files" {.txt .map}}
            {"All files" {*}}
        }]
    if {$path eq ""} { return }
    ::svvs::simulation_components::exportValueMapsTo $path $id
}

proc ::svvs::simulation_components::activateBlock {id} {
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return }
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set kind [::svvs::simulation_components::kind $module]
    if {$kind eq "clock"} {
        ::svvs::simulation_components::frequencyDialog $id
        return
    }
    if {$kind ne "input"} { return }
    set width [::svvs::simulation_components::config $module bitWidth 1]
    set action [::svvs::simulation_components::config $module clickAction edit]
    if {$action eq "pulse"} {
        ::svvs::simulation_components::applyInputBlockValue $id 1
        set pulseMs [::svvs::simulation_components::config $module pulseMs 100]
        after $pulseMs [list ::svvs::simulation_components::applyInputBlockValue $id 0]
        return
    }
    if {$action eq "slider" && $width > 1} {
        ::svvs::simulation_components::sliderDialog $id
        return
    }
    if {$width == 1 || $action eq "increment"} {
        set current [::svvs::simulation_components::config $module value 0]
        set next [expr {($current + 1) % (1 << $width)}]
        ::svvs::simulation_components::applyInputBlockValue $id $next
        return
    }
    ::svvs::simulation_components::editValueDialog $id
}

proc ::svvs::simulation_components::applyInputBlockValue {id value} {
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return }
    ::svvs::simulation_components::setConfig $id value $value
    if {$::svvs::diagram_simulation::active} {
        ::svvs::diagram_simulation::setSourceBlockValue $id $value
    }
}

proc ::svvs::simulation_components::sliderDialog {id} {
    variable editBlock
    variable editValue
    set editBlock $id
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set width [::svvs::simulation_components::config $module bitWidth 1]
    set editValue [::svvs::simulation_components::config $module value 0]
    catch {destroy .signalSlider}
    toplevel .signalSlider
    wm title .signalSlider "Signal slider"
    wm transient .signalSlider .
    ttk::label .signalSlider.name -text [::svvs::simulation_components::displayName $module]
    ttk::scale .signalSlider.scale -from 0 -to [expr {(1 << $width) - 1}] \
        -variable ::svvs::simulation_components::editValue -orient horizontal -length 260 \
        -command [list ::svvs::simulation_components::sliderChanged $id]
    ttk::label .signalSlider.value -textvariable ::svvs::simulation_components::editValue
    ttk::button .signalSlider.close -text "Close" -command {destroy .signalSlider}
    grid .signalSlider.name -row 0 -column 0 -columnspan 2 -sticky w -padx 14 -pady {14 7}
    grid .signalSlider.scale -row 1 -column 0 -padx {14 8} -pady {0 14}
    grid .signalSlider.value -row 1 -column 1 -padx {0 14}
    grid .signalSlider.close -row 2 -column 0 -columnspan 2 -pady {0 14}
}

proc ::svvs::simulation_components::sliderChanged {id rawValue} {
    variable editValue
    set editValue [expr {int(round($rawValue))}]
    ::svvs::simulation_components::applyInputBlockValue $id $editValue
}

proc ::svvs::simulation_components::toggleTrace {id} {
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set current [::svvs::simulation_components::config $module trace 1]
    ::svvs::simulation_components::setConfig $id trace [expr {!$current}]
    ::svvs::console::log [expr {$current ? "Sinal removido do grafico." : "Sinal adicionado ao grafico."}]
}

proc ::svvs::simulation_components::onDoubleClick {x y} {
    set hit [::svvs::canvas_blocks::hitAt $x $y]
    if {$hit eq ""} { return }
    if {[dict get $hit kind] eq "connection"} {
        ::svvs::canvas_connections::editAt $x $y
        return
    }
    if {[dict get $hit kind] ne "block"} { return }
    set blockTag [dict get $hit tag]
    set id [::svvs::canvas_blocks::blockIdFromTag $blockTag]
    if {![info exists ::svvs::canvas_blocks::blocks($id)]} { return }
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    switch -- [::svvs::simulation_components::kind $module] {
        input { ::svvs::simulation_components::activateBlock $id }
        clock { ::svvs::simulation_components::frequencyDialog $id }
    }
}

proc ::svvs::simulation_components::editValueDialog {id} {
    variable editBlock
    variable editValue
    set editBlock $id
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set width [::svvs::simulation_components::config $module bitWidth 1]
    set base [::svvs::simulation_components::config $module base bin]
    set editValue [::svvs::simulation_components::formatValue \
        [::svvs::simulation_components::config $module value 0] $width $base]
    ::svvs::simulation_components::showEditor "Input value" editValue commitValue
}

proc ::svvs::simulation_components::frequencyDialog {id} {
    variable editBlock
    variable editFrequency
    set editBlock $id
    set module [dict get $::svvs::canvas_blocks::blocks($id) module]
    set editFrequency [::svvs::simulation_components::config $module frequency 1.0]
    ::svvs::simulation_components::showEditor "Clock frequency (Hz)" editFrequency commitFrequency
}

proc ::svvs::simulation_components::showEditor {title variableName commitCommand} {
    catch {destroy .componentEditor}
    toplevel .componentEditor
    wm title .componentEditor $title
    wm transient .componentEditor .
    wm resizable .componentEditor 0 0
    ttk::label .componentEditor.label -text $title
    ttk::entry .componentEditor.value -textvariable ::svvs::simulation_components::$variableName -width 20
    ttk::button .componentEditor.apply -text "Apply" \
        -command ::svvs::simulation_components::$commitCommand
    grid .componentEditor.label -row 0 -column 0 -columnspan 2 -sticky w -padx 14 -pady {14 7}
    grid .componentEditor.value -row 1 -column 0 -padx {14 8} -pady {0 14}
    grid .componentEditor.apply -row 1 -column 1 -padx {0 14} -pady {0 14}
    bind .componentEditor.value <Return> ::svvs::simulation_components::$commitCommand
    focus .componentEditor.value
    .componentEditor.value selection range 0 end
}

proc ::svvs::simulation_components::commitValue {} {
    variable editBlock
    variable editValue
    set module [dict get $::svvs::canvas_blocks::blocks($editBlock) module]
    set width [::svvs::simulation_components::config $module bitWidth 1]
    set base [::svvs::simulation_components::config $module base bin]
    set parsed [::svvs::simulation_components::parseValue $editValue $base]
    if {![lindex $parsed 0]} {
        ::svvs::console::log "Valor invalido para o formato $base." warn
        return
    }
    set value [lindex $parsed 1]
    if {$value < 0 || $value >= (1 << $width)} {
        ::svvs::console::log "O valor nao cabe em $width bits." warn
        return
    }
    ::svvs::simulation_components::applyInputBlockValue $editBlock $value
    destroy .componentEditor
}

proc ::svvs::simulation_components::parseValue {text base} {
    set text [string trim $text]
    switch -- $base {
        bin {
            regsub -nocase {^0b} $text "" text
            if {![regexp {^[01]+$} $text]} { return [list 0 0] }
            set value 0
            foreach digit [split $text ""] { set value [expr {($value << 1) | $digit}] }
            return [list 1 $value]
        }
        hex {
            regsub -nocase {^0x} $text "" text
            if {![regexp -nocase {^[0-9a-f]+$} $text]} { return [list 0 0] }
            scan $text %x value
            return [list 1 $value]
        }
        default {
            if {![string is integer -strict $text]} { return [list 0 0] }
            return [list 1 $text]
        }
    }
}

proc ::svvs::simulation_components::setFrequency {id frequency} {
    ::svvs::simulation_components::setConfig $id frequency $frequency
}

proc ::svvs::simulation_components::commitFrequency {} {
    variable editBlock
    variable editFrequency
    if {![string is double -strict $editFrequency] || $editFrequency <= 0 || $editFrequency > 100} {
        ::svvs::console::log "Use uma frequencia entre 0 e 100 Hz." warn
        return
    }
    ::svvs::simulation_components::setFrequency $editBlock $editFrequency
    destroy .componentEditor
}

proc ::svvs::simulation_components::propertyLines {module} {
    set kind [::svvs::simulation_components::kind $module]
    if {$kind eq ""} { return {} }
    set lines [list "" "Simulation:"]
    lappend lines "Kind: $kind"
    set signalLabel [::svvs::simulation_components::config $module label ""]
    if {$signalLabel ne ""} { lappend lines "Name: $signalLabel" }
    lappend lines "Width: [::svvs::simulation_components::config $module bitWidth 1] bits"
    if {$kind eq "clock"} {
        lappend lines "Frequency: [::svvs::simulation_components::config $module frequency 1.0] Hz"
    } else {
        lappend lines "Format: [::svvs::simulation_components::config $module base bin]"
    }
    if {$kind eq "input"} {
        set action [::svvs::simulation_components::config $module clickAction edit]
        if {[::svvs::simulation_components::config $module bitWidth 1] == 1} { set action toggle }
        lappend lines "Click action: $action"
    }
    if {$kind in {input probe}} {
        set labelCount [dict size [::svvs::simulation_components::config $module valueMap {}]]
        lappend lines "Value labels: $labelCount"
    }
    lappend lines "Waveform: [expr {[::svvs::simulation_components::config $module trace 1] ? "shown" : "hidden"}]"
    lappend lines ""
    lappend lines "Right-click the block to configure it."
    return $lines
}
