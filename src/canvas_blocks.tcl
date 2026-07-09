namespace eval ::svvs::canvas_blocks {
    variable canvas ""
    variable blocks
    variable tagToBlock
    variable tagToPort
    variable selectedTag ""
    variable selectedTags
    variable dragTag ""
    variable resizeTag ""
    variable zoom 1.0
    variable showPortNames 1
    variable dragLastX 0
    variable dragLastY 0
    variable viewportPanning 0
    variable boxSelecting 0
    variable boxMoved 0
    variable boxStartX 0
    variable boxStartY 0
    variable boxRect ""
    array set blocks {}
    array set tagToBlock {}
    array set tagToPort {}
    set selectedTags {}
}

proc ::svvs::canvas_blocks::create {parent} {
    variable canvas
    set canvas [canvas $parent.canvas \
        -background [::svvs::theme::color bg] \
        -highlightthickness 0 \
        -borderwidth 0 \
        -scrollregion {-10000 -10000 10000 10000} \
        -xscrollincrement 1 \
        -yscrollincrement 1]

    bind $canvas <ButtonPress-1> {focus %W; ::svvs::canvas_blocks::onPress %x %y}
    bind $canvas <B1-Motion> {::svvs::canvas_blocks::onDrag %x %y}
    bind $canvas <ButtonRelease-1> {::svvs::canvas_blocks::onRelease %x %y}
    bind $canvas <ButtonPress-3> {::svvs::canvas_connections::showSimplifiedSideMenu %X %Y %x %y}
    bind $canvas <Double-1> {::svvs::simulation_components::onDoubleClick %x %y}
    bind $canvas <MouseWheel> {::svvs::canvas_blocks::onWheel %D %x %y}
    bind $canvas <Button-4> {::svvs::canvas_blocks::onWheel 1 %x %y}
    bind $canvas <Button-5> {::svvs::canvas_blocks::onWheel -1 %x %y}
    bind $canvas <ButtonPress-2> {::svvs::canvas_blocks::panStart %x %y}
    bind $canvas <B2-Motion> {::svvs::canvas_blocks::panMove %x %y}
    bind $canvas <ButtonRelease-2> {::svvs::canvas_blocks::panEnd}
    bind $canvas <Shift-ButtonPress-1> {focus %W; ::svvs::canvas_blocks::panStart %x %y; break}
    bind $canvas <Shift-B1-Motion> {::svvs::canvas_blocks::panMove %x %y; break}
    bind $canvas <Shift-ButtonRelease-1> {::svvs::canvas_blocks::panEnd; break}
    bind $canvas <Control-plus> {::svvs::canvas_blocks::keyboardZoom 1; break}
    bind $canvas <Control-equal> {::svvs::canvas_blocks::keyboardZoom 1; break}
    bind $canvas <Control-KP_Add> {::svvs::canvas_blocks::keyboardZoom 1; break}
    bind $canvas <Control-minus> {::svvs::canvas_blocks::keyboardZoom -1; break}
    bind $canvas <Control-KP_Subtract> {::svvs::canvas_blocks::keyboardZoom -1; break}
    bind $canvas <Control-Key-0> {::svvs::canvas_blocks::resetView; break}
    bind $canvas <Left> {::svvs::canvas_blocks::keyboardPan -40 0; break}
    bind $canvas <Right> {::svvs::canvas_blocks::keyboardPan 40 0; break}
    bind $canvas <Up> {::svvs::canvas_blocks::keyboardPan 0 -40; break}
    bind $canvas <Down> {::svvs::canvas_blocks::keyboardPan 0 40; break}

    after idle ::svvs::canvas_blocks::centerViewport

    return $canvas
}

proc ::svvs::canvas_blocks::loadSamples {modules} {
    variable canvas
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return
    }

    set x [::svvs::theme::scale 90]
    set y [::svvs::theme::scale 80]
    foreach module $modules {
        ::svvs::canvas_blocks::drawBlock $module $x $y
        incr x [::svvs::theme::scale 280]
        incr y [::svvs::theme::scale 72]
    }

    ::svvs::canvas_connections::drawConnection "uart_rx.data_out" "fifo_sync.din" 8
    ::svvs::canvas_connections::drawConnection "fifo_sync.dout" "uart_tx.data_in" 8
}

proc ::svvs::canvas_blocks::clearCanvas {} {
    variable canvas
    variable blocks
    variable tagToBlock
    variable tagToPort
    variable selectedTag
    variable selectedTags
    variable dragTag
    variable resizeTag
    variable zoom
    variable showPortNames
    variable viewportPanning
    variable boxSelecting
    variable boxMoved
    variable boxRect

    if {$canvas ne "" && [winfo exists $canvas]} {
        $canvas delete all
    }
    array unset blocks
    array unset tagToBlock
    array unset tagToPort
    array set blocks {}
    array set tagToBlock {}
    array set tagToPort {}
    set selectedTag ""
    set selectedTags {}
    set dragTag ""
    set resizeTag ""
    set zoom 1.0
    set showPortNames 1
    ::svvs::layout::setToolbarActive "Names" 1
    set viewportPanning 0
    set boxSelecting 0
    set boxMoved 0
    set boxRect ""
    ::svvs::canvas_connections::clearAll
    after idle ::svvs::canvas_blocks::centerViewport
}

proc ::svvs::canvas_blocks::exportDiagramData {} {
    variable canvas
    variable blocks
    variable zoom
    variable showPortNames

    set nodes {}
    foreach id [lsort [array names blocks]] {
        set block $blocks($id)
        set tag [dict get $block tag]
        set x [dict get $block x]
        set y [dict get $block y]
        set width [dict get $block width]
        set height [dict get $block height]

        if {$canvas ne "" && [winfo exists $canvas]} {
            foreach item [$canvas find withtag $tag] {
                set tags [$canvas gettags $item]
                if {[lsearch -exact $tags "block-body"] >= 0} {
                    set coords [$canvas coords $item]
                    if {[llength $coords] == 4} {
                        set x [lindex $coords 0]
                        set y [lindex $coords 1]
                        set width [expr {[lindex $coords 2] - [lindex $coords 0]}]
                        set height [expr {[lindex $coords 3] - [lindex $coords 1]}]
                    }
                    break
                }
            }
        }

        lappend nodes [dict create \
            id $id \
            module [dict get $block module] \
            x $x \
            y $y \
            width $width \
            height $height]
    }

    return [dict create \
        zoom $zoom \
        showPortNames $showPortNames \
        simplifiedConnections $::svvs::canvas_connections::simplifiedMode \
        simplifiedRoutes [::svvs::canvas_connections::exportSimplifiedRoutes] \
        nodes $nodes]
}

proc ::svvs::canvas_blocks::importDiagramData {data} {
    variable zoom
    variable showPortNames

    if {[dict exists $data zoom]} {
        set zoom [dict get $data zoom]
    }
    if {[dict exists $data showPortNames]} {
        set showPortNames [dict get $data showPortNames]
        ::svvs::layout::setToolbarActive "Names" $showPortNames
    }
    if {[dict exists $data simplifiedConnections]} {
        set ::svvs::canvas_connections::simplifiedMode [dict get $data simplifiedConnections]
        ::svvs::layout::setToolbarActive "Simple Wires" \
            $::svvs::canvas_connections::simplifiedMode
    }
    if {[dict exists $data simplifiedRoutes]} {
        ::svvs::canvas_connections::importSimplifiedRoutes [dict get $data simplifiedRoutes]
    }
    if {[dict exists $data nodes]} {
        foreach node [dict get $data nodes] {
            set id [dict get $node id]
            set module [dict get $node module]
            set x [dict get $node x]
            set y [dict get $node y]
            set width [dict get $node width]
            set height [dict get $node height]
            ::svvs::canvas_blocks::drawBlockWithId $id $module $x $y $width $height
        }
    }
    ::svvs::canvas_blocks::updateBlockSeq
    ::svvs::canvas_blocks::updateTextForZoom
}

proc ::svvs::canvas_blocks::drawBlock {module x y} {
    set ports [dict get $module ports]
    set inputs [::svvs::canvas_blocks::portsByDirection $ports input]
    set outputs [::svvs::canvas_blocks::portsByDirection $ports output]
    set rows [expr {max([llength $inputs], [llength $outputs])}]
    if {[::svvs::simulation_components::isBuiltin $module]} {
        if {[::svvs::simulation_components::isVirtual $module]} {
            set width [::svvs::theme::scale 64]
            set height [::svvs::theme::scale 64]
        } else {
            set width [::svvs::theme::scale 170]
            set rawHeight [expr {52 + ($rows * 20)}]
            set height [expr {max([::svvs::theme::scale 72], [::svvs::theme::scale $rawHeight])}]
        }
    } else {
        set width [::svvs::theme::scale 220]
        set rawHeight [expr {58 + ($rows * 24)}]
        set height [expr {max([::svvs::theme::scale 82], [::svvs::theme::scale $rawHeight])}]
    }
    set id "block[incr ::svvs::state(blockSeq)]"
    return [::svvs::canvas_blocks::drawBlockWithId $id $module $x $y $width $height]
}

proc ::svvs::canvas_blocks::drawBlockWithId {id module x y width height} {
    variable canvas
    variable blocks
    variable tagToBlock
    variable tagToPort

    set ports [dict get $module ports]
    set tag "block:$id"
    set blocks($id) [dict create id $id module $module x $x y $y width $width height $height tag $tag]

    $canvas create rectangle $x $y [expr {$x + $width}] [expr {$y + $height}] \
        -fill [::svvs::theme::color block] \
        -outline [::svvs::theme::color border] \
        -width [::svvs::theme::scale 1] \
        -tags [list $tag block-body]
    set headerHeight [::svvs::theme::scale 34]
    $canvas create rectangle $x $y [expr {$x + $width}] [expr {$y + $headerHeight}] \
        -fill [::svvs::theme::color blockHeader] \
        -outline [::svvs::theme::color border] \
        -tags [list $tag block-header]
    $canvas create text [expr {$x + [::svvs::theme::scale 12]}] [expr {$y + ($headerHeight / 2.0)}] \
        -text [dict get $module name] \
        -fill white \
        -font [::svvs::theme::font "Segoe UI" 10 bold] \
        -anchor w \
        -tags [list $tag block-title]

    set tagToBlock(resize:$id) $id
    foreach port $ports {
        set pName [dict get $port name]
        set pTag "port:$id:$pName"

        $canvas create oval 0 0 0 0 \
            -fill [::svvs::theme::color portIn] \
            -outline [::svvs::theme::color portIn] \
            -tags [list $tag $pTag port]
        $canvas create text 0 0 \
            -text [::svvs::canvas_blocks::portLabel $port] \
            -fill [::svvs::theme::color text] \
            -font [::svvs::theme::font "Consolas" 9] \
            -anchor w \
            -tags [list $tag $pTag port-label]

        set tagToBlock($pTag) $id
        set tagToPort($pTag) $port
    }

    $canvas create polygon 0 0 0 0 0 0 \
        -fill [::svvs::theme::color border] \
        -outline [::svvs::theme::color border] \
        -tags [list $tag "resize:$id" resize-handle]

    set tagToBlock($tag) $id
    ::svvs::canvas_blocks::layoutBlock $id
    ::svvs::simulation_components::decorateBlock $id
    ::svvs::canvas_blocks::updateTextForZoom
    if {$::svvs::canvas_connections::simplifiedMode} {
        ::svvs::canvas_blocks::setSimplifiedBlockStyle 1
    }
    return $id
}

proc ::svvs::canvas_blocks::updateBlockSeq {} {
    set maxSeq 0
    foreach id [array names ::svvs::canvas_blocks::blocks] {
        if {[regexp {^block([0-9]+)$} $id -> n] && $n > $maxSeq} {
            set maxSeq $n
        }
    }
    set ::svvs::state(blockSeq) $maxSeq
}

proc ::svvs::canvas_blocks::portsByDirection {ports direction} {
    set out {}
    foreach port $ports {
        if {[dict get $port direction] eq $direction} {
            lappend out $port
        }
    }
    return $out
}

proc ::svvs::canvas_blocks::portLabel {port} {
    set label [dict get $port name]
    set width [dict get $port width]
    if {$width > 1} {
        append label " \[[expr {$width - 1}]:0\]"
    }
    return $label
}

proc ::svvs::canvas_blocks::portY {y height index count} {
    if {$count <= 1} {
        return [expr {$y + max([::svvs::theme::scale 50], $height / 2.0)}]
    }
    set first [expr {$y + [::svvs::theme::scale 50]}]
    set last [expr {$y + $height - [::svvs::theme::scale 22]}]
    return [expr {$first + (($last - $first) * $index / double($count - 1))}]
}

proc ::svvs::canvas_blocks::layoutBlock {id} {
    variable canvas
    variable blocks

    set block $blocks($id)
    set module [dict get $block module]
    set x [dict get $block x]
    set y [dict get $block y]
    set width [dict get $block width]
    set height [dict get $block height]
    set tag [dict get $block tag]

    foreach item [$canvas find withtag $tag] {
        set tags [$canvas gettags $item]
        if {[lsearch -exact $tags "block-body"] >= 0} {
            $canvas coords $item $x $y [expr {$x + $width}] [expr {$y + $height}]
        } elseif {[lsearch -exact $tags "block-header"] >= 0} {
            $canvas coords $item $x $y [expr {$x + $width}] [expr {$y + [::svvs::theme::scale 34]}]
        } elseif {[lsearch -exact $tags "block-title"] >= 0} {
            $canvas coords $item [expr {$x + [::svvs::theme::scale 12]}] \
                [expr {$y + ([::svvs::theme::scale 34] / 2.0)}]
        } elseif {[lsearch -exact $tags "resize-handle"] >= 0} {
            set handleSize [::svvs::theme::scale 12]
            $canvas coords $item \
                [expr {$x + $width - $handleSize}] [expr {$y + $height}] \
                [expr {$x + $width}] [expr {$y + $height}] \
                [expr {$x + $width}] [expr {$y + $height - $handleSize}]
        }
    }

    set ports [dict get $module ports]
    set inputs [::svvs::canvas_blocks::portsByDirection $ports input]
    set outputs [::svvs::canvas_blocks::portsByDirection $ports output]
    ::svvs::canvas_blocks::layoutPorts $id $inputs input $x $y $width $height
    ::svvs::canvas_blocks::layoutPorts $id $outputs output $x $y $width $height
    ::svvs::simulation_components::layoutDecoration $id
}

proc ::svvs::canvas_blocks::layoutPorts {id ports direction x y width height} {
    variable canvas

    set compactVirtual 0
    if {[info exists ::svvs::canvas_blocks::blocks($id)]} {
        set module [dict get $::svvs::canvas_blocks::blocks($id) module]
        set compactVirtual [::svvs::simulation_components::isVirtual $module]
    }

    set count [llength $ports]
    set index 0
    set portRadius [::svvs::theme::scale 5]
    foreach port $ports {
        set pName [dict get $port name]
        set pTag "port:$id:$pName"
        if {$compactVirtual} {
            set rowY [expr {$y + ($height / 2.0)}]
        } else {
            set rowY [::svvs::canvas_blocks::portY $y $height $index $count]
        }

        if {$direction eq "input"} {
            set px [expr {$compactVirtual ? $x + $portRadius : $x}]
            set tx [expr {$x + [::svvs::theme::scale 18]}]
            set anchor w
            set color [::svvs::theme::color portIn]
        } else {
            set px [expr {$compactVirtual ? $x + $width - $portRadius : $x + $width}]
            set tx [expr {$x + $width - [::svvs::theme::scale 18]}]
            set anchor e
            set color [::svvs::theme::color portOut]
        }

        foreach item [$canvas find withtag $pTag] {
            set tags [$canvas gettags $item]
            if {[lsearch -exact $tags "port"] >= 0} {
                $canvas coords $item [expr {$px - $portRadius}] [expr {$rowY - $portRadius}] \
                    [expr {$px + $portRadius}] [expr {$rowY + $portRadius}]
                $canvas itemconfigure $item -fill $color -outline $color
            } elseif {[lsearch -exact $tags "port-label"] >= 0} {
                $canvas coords $item $tx $rowY
                $canvas itemconfigure $item -anchor $anchor -text [::svvs::canvas_blocks::portLabel $port]
            }
        }
        incr index
    }
}

proc ::svvs::canvas_blocks::containsScreenPoint {rootX rootY} {
    variable canvas
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return 0
    }

    set left [winfo rootx $canvas]
    set top [winfo rooty $canvas]
    set right [expr {$left + [winfo width $canvas]}]
    set bottom [expr {$top + [winfo height $canvas]}]
    return [expr {$rootX >= $left && $rootX <= $right && $rootY >= $top && $rootY <= $bottom}]
}

proc ::svvs::canvas_blocks::addModuleAtScreenPoint {module rootX rootY} {
    variable canvas
    set localX [expr {$rootX - [winfo rootx $canvas]}]
    set localY [expr {$rootY - [winfo rooty $canvas]}]
    set x [$canvas canvasx $localX]
    set y [$canvas canvasy $localY]
    ::svvs::canvas_blocks::drawBlock [::svvs::canvas_blocks::nextInstanceModule $module] $x $y
}

proc ::svvs::canvas_blocks::addModuleAtVisibleCenter {module} {
    variable canvas
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return
    }

    set x [$canvas canvasx [expr {[winfo width $canvas] / 2 - [::svvs::theme::scale 110]}]]
    set y [$canvas canvasy [expr {[winfo height $canvas] / 2 - [::svvs::theme::scale 70]}]]
    ::svvs::canvas_blocks::drawBlock [::svvs::canvas_blocks::nextInstanceModule $module] $x $y
}

proc ::svvs::canvas_blocks::nextInstanceModule {module} {
    set name [dict get $module name]
    set instance "u_${name}_$::svvs::state(blockSeq)"
    dict set module instance $instance
    return $module
}

proc ::svvs::canvas_blocks::onPress {x y} {
    variable canvas
    variable selectedTag
    variable selectedTags
    variable dragTag
    variable resizeTag
    variable dragLastX
    variable dragLastY

    focus .
    set hit [::svvs::canvas_blocks::hitAt $x $y]
    set hitKind [expr {$hit eq "" ? "" : [dict get $hit kind]}]
    set hitTag [expr {$hit eq "" ? "" : [dict get $hit tag]}]

    if {$hitKind eq "resize"} {
        set handleTag $hitTag
        set selectedTag $handleTag
        set selectedTags {}
        set resizeTag $handleTag
        set dragLastX $x
        set dragLastY $y
        ::svvs::canvas_blocks::paintSelection
        ::svvs::canvas_blocks::showBlockProperties "block:[lindex [split $handleTag :] 1]"
        return
    }

    if {$hitKind eq "port"} {
        set portTag $hitTag
        ::svvs::canvas_blocks::selectPort $portTag
        ::svvs::canvas_connections::handlePortClick $portTag
        return
    }

    if {$hitKind eq "block"} {
        set blockTag $hitTag
        set selectedTag $blockTag
        if {[lsearch -exact $selectedTags $blockTag] < 0} {
            set selectedTags [list $blockTag]
        }
        set dragTag $blockTag
        set dragLastX $x
        set dragLastY $y
        ::svvs::canvas_blocks::paintSelection
        ::svvs::canvas_blocks::showSelectionProperties
    } elseif {$hitKind eq "connection" && [::svvs::canvas_connections::selectAt $x $y]} {
        set dragTag ""
        set resizeTag ""
        set selectedTags {}
        ::svvs::canvas_connections::beginRouteDragAt $selectedTag $x $y
    } else {
        ::svvs::canvas_connections::cancelPending
        ::svvs::canvas_blocks::beginBoxSelection $x $y
    }
}

proc ::svvs::canvas_blocks::onDrag {x y} {
    variable canvas
    variable dragTag
    variable resizeTag
    variable dragLastX
    variable dragLastY
    variable viewportPanning
    variable boxSelecting

    if {$viewportPanning} {
        ::svvs::canvas_blocks::panMove $x $y
        return
    }

    if {$boxSelecting} {
        ::svvs::canvas_blocks::updateBoxSelection $x $y
        return
    }

    if {[::svvs::canvas_connections::dragRouteTo $x $y]} {
        return
    }

    if {$resizeTag ne ""} {
        set dx [expr {$x - $dragLastX}]
        set dy [expr {$y - $dragLastY}]
        ::svvs::canvas_blocks::resizeBlockBy $resizeTag $dx $dy
        set dragLastX $x
        set dragLastY $y
        ::svvs::canvas_connections::refreshAll
        if {$::svvs::diagram_simulation::active} { ::svvs::diagram_simulation::redraw }
        return
    }

    if {$dragTag eq ""} {
        return
    }

    set dx [expr {$x - $dragLastX}]
    set dy [expr {$y - $dragLastY}]
    ::svvs::canvas_blocks::moveSelectedBlocks $dragTag $dx $dy
    set dragLastX $x
    set dragLastY $y
    ::svvs::canvas_connections::refreshAll
    if {$::svvs::diagram_simulation::active} { ::svvs::diagram_simulation::redraw }
}

proc ::svvs::canvas_blocks::onRelease {x y} {
    variable dragTag
    variable resizeTag
    variable viewportPanning
    variable boxSelecting
    if {$viewportPanning} {
        ::svvs::canvas_blocks::panEnd
        return
    }
    if {$boxSelecting} {
        ::svvs::canvas_blocks::finishBoxSelection $x $y
        return
    }
    if {$resizeTag ne ""} {
        ::svvs::console::log "Bloco redimensionado."
    }
    if {$dragTag ne ""} {
        ::svvs::console::log "Bloco reposicionado."
    }
    ::svvs::canvas_connections::endRouteDrag
    set dragTag ""
    set resizeTag ""
}

proc ::svvs::canvas_blocks::beginBoxSelection {x y} {
    variable canvas
    variable selectedTag
    variable selectedTags
    variable boxSelecting
    variable boxMoved
    variable boxStartX
    variable boxStartY
    variable boxRect

    set selectedTag ""
    set selectedTags {}
    ::svvs::canvas_blocks::paintSelection
    ::svvs::properties_panel::showWelcome

    set boxSelecting 1
    set boxMoved 0
    set boxStartX [$canvas canvasx $x]
    set boxStartY [$canvas canvasy $y]
    catch {$canvas delete selection-box}
    set boxRect [$canvas create rectangle $boxStartX $boxStartY $boxStartX $boxStartY \
        -outline [::svvs::theme::color accentHover] \
        -width [::svvs::theme::scale 1] \
        -dash [list [::svvs::theme::scale 4] [::svvs::theme::scale 3]] \
        -tags [list selection-box]]
}

proc ::svvs::canvas_blocks::updateBoxSelection {x y} {
    variable canvas
    variable boxMoved
    variable boxStartX
    variable boxStartY
    variable boxRect

    if {$boxRect eq ""} {
        return
    }
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]
    if {abs($cx - $boxStartX) > [::svvs::theme::scale 3] ||
        abs($cy - $boxStartY) > [::svvs::theme::scale 3]} {
        set boxMoved 1
    }
    $canvas coords $boxRect $boxStartX $boxStartY $cx $cy
}

proc ::svvs::canvas_blocks::finishBoxSelection {x y} {
    variable canvas
    variable selectedTag
    variable selectedTags
    variable boxSelecting
    variable boxMoved
    variable boxStartX
    variable boxStartY
    variable boxRect

    set boxSelecting 0
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]
    set x1 [expr {min($boxStartX, $cx)}]
    set y1 [expr {min($boxStartY, $cy)}]
    set x2 [expr {max($boxStartX, $cx)}]
    set y2 [expr {max($boxStartY, $cy)}]
    if {$boxRect ne ""} {
        catch {$canvas delete $boxRect}
        set boxRect ""
    }

    if {!$boxMoved} {
        set selectedTag ""
        set selectedTags {}
        ::svvs::canvas_blocks::paintSelection
        ::svvs::properties_panel::showWelcome
        return
    }

    set selectedTags [::svvs::canvas_blocks::blocksInBox $x1 $y1 $x2 $y2]
    if {[llength $selectedTags] > 0} {
        set selectedTag [lindex $selectedTags 0]
        ::svvs::canvas_blocks::showSelectionProperties
        ::svvs::console::log "Blocos selecionados: [llength $selectedTags]"
    } else {
        set selectedTag ""
        ::svvs::properties_panel::showWelcome
    }
    ::svvs::canvas_blocks::paintSelection
}

proc ::svvs::canvas_blocks::blocksInBox {x1 y1 x2 y2} {
    variable canvas
    set result {}
    foreach item [$canvas find overlapping $x1 $y1 $x2 $y2] {
        set tags [$canvas gettags $item]
        if {[lsearch -exact $tags "block-body"] < 0} {
            continue
        }
        set blockTag [::svvs::canvas_blocks::findTag $tags "block:"]
        if {$blockTag ne "" && [lsearch -exact $result $blockTag] < 0} {
            lappend result $blockTag
        }
    }
    return $result
}

proc ::svvs::canvas_blocks::moveSelectedBlocks {fallbackTag dx dy} {
    variable canvas
    variable selectedTags
    set targets $selectedTags
    if {[llength $targets] == 0} {
        set targets [list $fallbackTag]
    }
    foreach blockTag $targets {
        if {![string match "block:*" $blockTag]} {
            continue
        }
        $canvas move $blockTag $dx $dy
        ::svvs::canvas_blocks::moveBlockData $blockTag $dx $dy
    }
}

proc ::svvs::canvas_blocks::moveBlockData {blockTag dx dy} {
    variable blocks
    set id [::svvs::canvas_blocks::blockIdFromTag $blockTag]
    if {![info exists blocks($id)]} {
        return
    }
    dict set blocks($id) x [expr {[dict get $blocks($id) x] + $dx}]
    dict set blocks($id) y [expr {[dict get $blocks($id) y] + $dy}]
}

proc ::svvs::canvas_blocks::resizeBlockBy {handleTag dx dy} {
    variable blocks
    set id [lindex [split $handleTag :] 1]
    if {![info exists blocks($id)]} {
        return
    }
    set module [dict get $blocks($id) module]
    set kind [::svvs::simulation_components::kind $module]
    if {$kind in {input probe}} {
        set minWidth [::svvs::theme::scale 44]
        set minHeight [::svvs::theme::scale 44]
    } else {
        set minWidth [::svvs::theme::scale 140]
        set minHeight [::svvs::theme::scale 70]
    }
    set width [expr {max($minWidth, [dict get $blocks($id) width] + $dx)}]
    set height [expr {max($minHeight, [dict get $blocks($id) height] + $dy)}]
    dict set blocks($id) width $width
    dict set blocks($id) height $height
    ::svvs::canvas_blocks::layoutBlock $id
    ::svvs::simulation_components::updateDisplay $id
}

proc ::svvs::canvas_blocks::onWheel {delta x y} {
    variable canvas
    variable zoom
    set factor 1.08
    if {$delta < 0} {
        set factor 0.92
    }
    set nextZoom [expr {$zoom * $factor}]
    if {$nextZoom < 0.25 || $nextZoom > 3.0} {
        return
    }
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]
    set zoom $nextZoom
    $canvas scale all $cx $cy $factor $factor
    ::svvs::canvas_connections::scaleRoutes $cx $cy $factor
    ::svvs::canvas_blocks::updateTextForZoom
    ::svvs::canvas_connections::refreshAll
    if {$::svvs::diagram_simulation::active} { ::svvs::diagram_simulation::redraw }
}

proc ::svvs::canvas_blocks::keyboardZoom {direction} {
    variable canvas
    if {$canvas eq "" || ![winfo exists $canvas]} { return }
    ::svvs::canvas_blocks::onWheel $direction \
        [expr {[winfo width $canvas] / 2}] [expr {[winfo height $canvas] / 2}]
}

proc ::svvs::canvas_blocks::keyboardPan {dx dy} {
    variable canvas
    if {$canvas eq "" || ![winfo exists $canvas]} { return }
    if {$dx != 0} { $canvas xview scroll [::svvs::theme::scale $dx] units }
    if {$dy != 0} { $canvas yview scroll [::svvs::theme::scale $dy] units }
}

proc ::svvs::canvas_blocks::resetView {} {
    variable canvas
    variable zoom
    if {$canvas eq "" || ![winfo exists $canvas] || $zoom == 1.0} { return }
    set cx [$canvas canvasx [expr {[winfo width $canvas] / 2.0}]]
    set cy [$canvas canvasy [expr {[winfo height $canvas] / 2.0}]]
    set factor [expr {1.0 / $zoom}]
    $canvas scale all $cx $cy $factor $factor
    ::svvs::canvas_connections::scaleRoutes $cx $cy $factor
    set zoom 1.0
    ::svvs::canvas_blocks::updateTextForZoom
    ::svvs::canvas_connections::refreshAll
    if {$::svvs::diagram_simulation::active} { ::svvs::diagram_simulation::redraw }
}

proc ::svvs::canvas_blocks::scaledFontSize {base min max} {
    variable zoom
    set size [expr {int(round([::svvs::theme::scale $base] * $zoom))}]
    set scaledMin [::svvs::theme::scale $min]
    set scaledMax [::svvs::theme::scale $max]
    if {$size < $scaledMin} {
        return $scaledMin
    }
    if {$size > $scaledMax} {
        return $scaledMax
    }
    return $size
}

proc ::svvs::canvas_blocks::updateTextForZoom {} {
    variable canvas
    variable showPortNames
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return
    }

    set titleSize [::svvs::canvas_blocks::scaledFontSize 10 6 20]
    set portSize [::svvs::canvas_blocks::scaledFontSize 9 4 18]
    foreach item [$canvas find withtag block-title] {
        if {[lsearch -exact [$canvas gettags $item] simulation-hidden] >= 0} {
            $canvas itemconfigure $item -state hidden
            continue
        }
        $canvas itemconfigure $item -font [list {Segoe UI} $titleSize bold]
    }
    foreach item [$canvas find withtag port-label] {
        if {[lsearch -exact [$canvas gettags $item] simulation-hidden] >= 0} {
            $canvas itemconfigure $item -state hidden
            continue
        }
        $canvas itemconfigure $item -font [list Consolas $portSize]
        if {$showPortNames && !$::svvs::canvas_connections::simplifiedMode} {
            $canvas itemconfigure $item -state normal
        } else {
            $canvas itemconfigure $item -state hidden
        }
    }
}

proc ::svvs::canvas_blocks::setSimplifiedBlockStyle {enabled} {
    variable canvas
    variable blocks
    variable zoom
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return
    }

    foreach id [array names blocks] {
        set tag [dict get $blocks($id) tag]
        set bodyCoords ""
        set headerCoords ""
        foreach item [$canvas find withtag $tag] {
            set tags [$canvas gettags $item]
            if {[lsearch -exact $tags "block-body"] >= 0} {
                set bodyCoords [$canvas coords $item]
            } elseif {[lsearch -exact $tags "block-header"] >= 0} {
                set headerCoords [$canvas coords $item]
            }
        }
        if {[llength $bodyCoords] != 4} {
            continue
        }

        lassign $bodyCoords x1 y1 x2 y2
        foreach item [$canvas find withtag $tag] {
            set tags [$canvas gettags $item]
            if {[lsearch -exact $tags simulation-hidden] >= 0} {
                $canvas itemconfigure $item -state hidden
                continue
            }
            if {[lsearch -exact $tags "block-header"] >= 0 ||
                [lsearch -exact $tags "port"] >= 0 ||
                [lsearch -exact $tags "port-label"] >= 0} {
                $canvas itemconfigure $item -state [expr {$enabled ? "hidden" : "normal"}]
            } elseif {[lsearch -exact $tags "resize-handle"] >= 0} {
                $canvas itemconfigure $item -state normal
            } elseif {[lsearch -exact $tags "block-title"] >= 0} {
                $canvas itemconfigure $item -state normal
                if {$enabled} {
                    $canvas coords $item [expr {($x1 + $x2) / 2.0}] [expr {($y1 + $y2) / 2.0}]
                    $canvas itemconfigure $item -anchor center
                } else {
                    if {[llength $headerCoords] == 4} {
                        set titleX [expr {[lindex $headerCoords 0] + ([::svvs::theme::scale 12] * $zoom)}]
                        set titleY [expr {([lindex $headerCoords 1] + [lindex $headerCoords 3]) / 2.0}]
                    } else {
                        set titleX [expr {$x1 + (12.0 * $zoom)}]
                        set titleY [expr {$y1 + (17.0 * $zoom)}]
                    }
                    $canvas coords $item $titleX $titleY
                    $canvas itemconfigure $item -anchor w
                }
            }
        }
    }
}

proc ::svvs::canvas_blocks::togglePortNames {} {
    variable showPortNames
    set showPortNames [expr {!$showPortNames}]
    ::svvs::layout::setToolbarActive "Names" $showPortNames
    ::svvs::canvas_blocks::updateTextForZoom
    if {$showPortNames} {
        ::svvs::console::log "Nomes das portas visiveis."
    } else {
        ::svvs::console::log "Nomes das portas ocultos."
    }
}

proc ::svvs::canvas_blocks::panStart {x y} {
    variable canvas
    variable viewportPanning
    set viewportPanning 1
    $canvas scan mark $x $y
    $canvas configure -cursor fleur
}

proc ::svvs::canvas_blocks::panMove {x y} {
    variable canvas
    variable viewportPanning
    if {!$viewportPanning} {
        return
    }
    $canvas scan dragto $x $y 1
}

proc ::svvs::canvas_blocks::panEnd {} {
    variable canvas
    variable viewportPanning
    set viewportPanning 0
    if {$canvas ne "" && [winfo exists $canvas]} {
        $canvas configure -cursor ""
    }
}

proc ::svvs::canvas_blocks::centerViewport {} {
    variable canvas
    if {$canvas ne "" && [winfo exists $canvas]} {
        $canvas xview moveto 0.5
        $canvas yview moveto 0.5
    }
}

proc ::svvs::canvas_blocks::tagAt {x y prefix} {
    variable canvas
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]
    foreach item [lreverse [$canvas find overlapping \
        [expr {$cx - 7}] [expr {$cy - 7}] [expr {$cx + 7}] [expr {$cy + 7}]]] {
        set tag [::svvs::canvas_blocks::findTag [$canvas gettags $item] $prefix]
        if {$tag ne ""} {
            return $tag
        }
    }
    return ""
}

proc ::svvs::canvas_blocks::hitAt {x y} {
    variable canvas
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]
    foreach item [lreverse [$canvas find overlapping \
        [expr {$cx - 7}] [expr {$cy - 7}] [expr {$cx + 7}] [expr {$cy + 7}]]] {
        set tags [$canvas gettags $item]

        set connTag [::svvs::canvas_blocks::connectionTagFromTags $tags]
        if {$connTag ne ""} {
            return [dict create kind connection tag $connTag item $item]
        }

        if {[lsearch -exact $tags "resize-handle"] >= 0} {
            set tag [::svvs::canvas_blocks::findTag $tags "resize:"]
            if {$tag ne ""} {
                return [dict create kind resize tag $tag item $item]
            }
        }

        if {[lsearch -exact $tags "port"] >= 0} {
            set tag [::svvs::canvas_blocks::findTag $tags "port:"]
            if {$tag ne ""} {
                return [dict create kind port tag $tag item $item]
            }
        }

        set blockTag [::svvs::canvas_blocks::findTag $tags "block:"]
        if {$blockTag ne ""} {
            return [dict create kind block tag $blockTag item $item]
        }
    }
    return ""
}

proc ::svvs::canvas_blocks::connectionTagFromTags {tags} {
    set isConnection 0
    foreach marker {
        connection connection-hit connection-range-label connection-route-handle
        simplified-wire simplified-hit simplified-route-handle
    } {
        if {[lsearch -exact $tags $marker] >= 0} {
            set isConnection 1
            break
        }
    }
    if {!$isConnection} {
        return ""
    }
    foreach tag $tags {
        if {[string match "conn:*" $tag] || [string match "simple-pair:*" $tag]} {
            return $tag
        }
    }
    return ""
}

proc ::svvs::canvas_blocks::findTag {tags prefix} {
    foreach tag $tags {
        if {[string match "$prefix*" $tag]} {
            return $tag
        }
    }
    return ""
}

proc ::svvs::canvas_blocks::blockIdFromTag {tag} {
    return [lindex [split $tag :] 1]
}

proc ::svvs::canvas_blocks::moduleForBlockTag {blockTag} {
    variable blocks
    set id [::svvs::canvas_blocks::blockIdFromTag $blockTag]
    return [dict get $blocks($id) module]
}

proc ::svvs::canvas_blocks::selectedBlockId {} {
    variable selectedTag
    if {[regexp {^block:([^:]+)$} $selectedTag -> id] &&
        [info exists ::svvs::canvas_blocks::blocks($id)]} {
        return $id
    }
    if {[regexp {^resize:([^:]+)$} $selectedTag -> id] &&
        [info exists ::svvs::canvas_blocks::blocks($id)]} {
        return $id
    }
    if {[regexp {^port:([^:]+):} $selectedTag -> id] &&
        [info exists ::svvs::canvas_blocks::blocks($id)]} {
        return $id
    }
    return ""
}

proc ::svvs::canvas_blocks::portInfo {portTag} {
    variable tagToBlock
    variable tagToPort
    set blockId $tagToBlock($portTag)
    set blockTag "block:$blockId"
    set module [::svvs::canvas_blocks::moduleForBlockTag $blockTag]
    return [dict create module $module port $tagToPort($portTag)]
}

proc ::svvs::canvas_blocks::portCenter {portTag} {
    variable canvas
    set items [$canvas find withtag $portTag]
    foreach item $items {
        if {[lsearch -exact [$canvas gettags $item] "port"] >= 0} {
            set c [$canvas coords $item]
            return [list [expr {([lindex $c 0] + [lindex $c 2]) / 2.0}] [expr {([lindex $c 1] + [lindex $c 3]) / 2.0}]]
        }
    }
    return [list 0 0]
}

proc ::svvs::canvas_blocks::selectPort {portTag} {
    variable selectedTag
    variable selectedTags
    set selectedTag $portTag
    set selectedTags {}
    ::svvs::canvas_blocks::paintSelection
    set info [::svvs::canvas_blocks::portInfo $portTag]
    ::svvs::properties_panel::showPort [dict get $info module] [dict get $info port]
    ::svvs::console::log "Porta selecionada: [dict get [dict get $info module] name].[dict get [dict get $info port] name]"
}

proc ::svvs::canvas_blocks::showBlockProperties {blockTag} {
    set module [::svvs::canvas_blocks::moduleForBlockTag $blockTag]
    ::svvs::properties_panel::showModule $module
    ::svvs::console::log "Bloco selecionado: [dict get $module instance]"
}

proc ::svvs::canvas_blocks::showSelectionProperties {} {
    variable selectedTags
    if {[llength $selectedTags] == 1} {
        ::svvs::canvas_blocks::showBlockProperties [lindex $selectedTags 0]
        return
    }
    set lines [list \
        "Type: Multiple Selection" \
        "Blocks: [llength $selectedTags]" \
        "" \
        "Selected instances:"]
    foreach blockTag $selectedTags {
        if {[catch {set module [::svvs::canvas_blocks::moduleForBlockTag $blockTag]}]} {
            continue
        }
        lappend lines "  [dict get $module instance]"
    }
    ::svvs::properties_panel::setText [join $lines "\n"]
}

proc ::svvs::canvas_blocks::paintSelection {} {
    variable canvas
    variable selectedTag
    variable selectedTags

    foreach item [$canvas find withtag block-body] {
        $canvas itemconfigure $item -outline [::svvs::theme::color border] \
            -width [::svvs::theme::scale 1]
    }
    foreach item [$canvas find withtag port] {
        $canvas itemconfigure $item -width [::svvs::theme::scale 1]
    }
    foreach item [$canvas find withtag resize-handle] {
        $canvas itemconfigure $item -fill [::svvs::theme::color border]
    }
    if {[string match "conn:*" $selectedTag]} {
        ::svvs::canvas_connections::paintSelection $selectedTag
    } else {
        ::svvs::canvas_connections::paintSelection
    }

    if {$selectedTag eq ""} {
        return
    }

    set tagsToPaint $selectedTags
    if {[llength $tagsToPaint] == 0} {
        set tagsToPaint [list $selectedTag]
    }
    foreach tagToPaint $tagsToPaint {
        foreach item [$canvas find withtag $tagToPaint] {
        set tags [$canvas gettags $item]
        if {[lsearch -exact $tags "block-body"] >= 0} {
            $canvas itemconfigure $item -outline [::svvs::theme::color accent] \
                -width [::svvs::theme::scale 2]
        }
        if {[lsearch -exact $tags "port"] >= 0} {
            $canvas itemconfigure $item -outline white -width [::svvs::theme::scale 2]
        }
        if {[lsearch -exact $tags "resize-handle"] >= 0} {
            $canvas itemconfigure $item -fill [::svvs::theme::color accent]
        }
        }
    }
}

proc ::svvs::canvas_blocks::clearSelection {} {
    variable selectedTag
    variable selectedTags
    set selectedTag ""
    set selectedTags {}
    ::svvs::canvas_blocks::paintSelection
    ::svvs::properties_panel::showWelcome
}

proc ::svvs::canvas_blocks::removeBlockData {blockTag} {
    variable blocks
    variable tagToBlock
    variable tagToPort

    set id [::svvs::canvas_blocks::blockIdFromTag $blockTag]
    foreach portTag [array names tagToBlock] {
        if {$tagToBlock($portTag) eq $id} {
            catch {unset tagToBlock($portTag)}
            catch {unset tagToPort($portTag)}
        }
    }
    catch {unset blocks($id)}
}

proc ::svvs::canvas_blocks::deleteSelected {} {
    variable canvas
    variable selectedTag
    variable selectedTags

    if {[llength $selectedTags] > 0} {
        foreach blockTag $selectedTags {
            if {![string match "block:*" $blockTag]} {
                continue
            }
            ::svvs::canvas_connections::removeForBlock $blockTag
            $canvas delete $blockTag
            ::svvs::canvas_blocks::removeBlockData $blockTag
        }
        ::svvs::console::log "Blocos removidos: [llength $selectedTags]"
        set selectedTag ""
        set selectedTags {}
        ::svvs::properties_panel::showWelcome
        return
    }

    if {$selectedTag eq ""} {
        return
    }
    if {[string match "block:*" $selectedTag]} {
        ::svvs::canvas_connections::removeForBlock $selectedTag
        $canvas delete $selectedTag
        ::svvs::canvas_blocks::removeBlockData $selectedTag
        ::svvs::console::log "Bloco removido."
    } elseif {[string match "conn:*" $selectedTag]} {
        $canvas delete $selectedTag
        ::svvs::canvas_connections::remove $selectedTag
        ::svvs::console::log "Conexao removida."
    }
    set selectedTag ""
    set selectedTags {}
    ::svvs::properties_panel::showWelcome
}

proc ::svvs::canvas_blocks::cancelAction {} {
    variable canvas
    variable boxSelecting
    variable boxMoved
    variable boxRect
    if {$boxRect ne "" && $canvas ne "" && [winfo exists $canvas]} {
        catch {$canvas delete $boxRect}
    }
    set boxSelecting 0
    set boxMoved 0
    set boxRect ""
    ::svvs::canvas_connections::cancel
    ::svvs::console::log "Acao cancelada."
}
