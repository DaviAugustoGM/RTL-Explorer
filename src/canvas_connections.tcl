namespace eval ::svvs::canvas_connections {
    variable connections
    variable pendingPort ""
    variable routeDragId ""
    variable routeDragField ""
    variable routeDragMoved 0
    variable simplifiedMode 0
    variable simplifiedRoutes
    variable selectedSimplePair ""
    variable simpleDragPair ""
    variable simpleDragField ""
    array set simplifiedRoutes {}
    variable seq 0
    array set connections {}
}

proc ::svvs::canvas_connections::handlePortClick {portTag} {
    variable pendingPort

    if {$pendingPort eq ""} {
        set pendingPort $portTag
        ::svvs::console::log "Inicio de conexao: [::svvs::canvas_connections::portLabel $portTag]"
        return
    }

    if {$pendingPort eq $portTag} {
        set pendingPort ""
        ::svvs::console::log "Conexao cancelada."
        return
    }

    ::svvs::canvas_connections::drawConnection $pendingPort $portTag
    set pendingPort ""
}

proc ::svvs::canvas_connections::drawConnection {from to {width ""}} {
    variable connections
    variable seq
    set canvas $::svvs::canvas_blocks::canvas
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return
    }

    set fromTag [::svvs::canvas_connections::resolvePortTag $from]
    set toTag [::svvs::canvas_connections::resolvePortTag $to]
    if {$fromTag eq "" || $toTag eq "" ||
        ![::svvs::canvas_connections::portIsLive $fromTag] ||
        ![::svvs::canvas_connections::portIsLive $toTag]} {
        return
    }

    if {![::svvs::simulation_components::adaptConnection $fromTag $toTag]} {
        return
    }

    if {$width eq ""} {
        set width [::svvs::canvas_connections::connectionWidth $fromTag $toTag]
    }

    set id "conn:[incr seq]"
    return [::svvs::canvas_connections::drawConnectionWithId $id $fromTag $toTag $width]
}

proc ::svvs::canvas_connections::drawConnectionWithId {id fromTag toTag width {routeX1 ""} {routeY ""} {routeX2 ""}} {
    variable connections
    variable seq
    set canvas $::svvs::canvas_blocks::canvas
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return ""
    }
    if {[regexp {^conn:([0-9]+)$} $id -> n] && $n > $seq} {
        set seq $n
    }

    set hitId "$id:hit"
    set coords [::svvs::canvas_connections::wireCoords $fromTag $toTag $routeX1 $routeY $routeX2]
    $canvas create line {*}$coords \
        -fill [::svvs::theme::color bg] \
        -width 12 \
        -smooth false \
        -tags [list $id $hitId connection-hit]
    $canvas create line {*}$coords \
        -fill [::svvs::theme::color wire] \
        -width [expr {$width > 1 ? 3 : 2}] \
        -smooth false \
        -arrow last \
        -tags [list $id connection]
    foreach handle {source middle target} {
        $canvas create oval 0 0 0 0 \
            -fill [::svvs::theme::color accent] \
            -outline white \
            -width 1 \
            -state hidden \
            -tags [list $id connection-route-handle "route-handle:$handle"]
    }
    $canvas lower $hitId

    set signal [::svvs::canvas_connections::signalName $fromTag]
    set connections($id) [dict create \
        id $id from $fromTag to $toTag signal $signal width $width \
        routeX1 $routeX1 routeY $routeY routeX2 $routeX2]
    ::svvs::simulation_components::assignConnectionNames $fromTag $toTag
    ::svvs::canvas_connections::updateGeometry $id
    ::svvs::canvas_connections::refreshDisplay
    ::svvs::console::log "Conexao criada: [::svvs::canvas_connections::portLabel $fromTag] -> [::svvs::canvas_connections::portLabel $toTag]" ok
    return $id
}

proc ::svvs::canvas_connections::autoConnect {} {
    variable connections

    ::svvs::canvas_connections::removeDangling

    set outputs {}
    set inputs {}
    foreach portTag [lsort [array names ::svvs::canvas_blocks::tagToPort]] {
        if {![::svvs::canvas_connections::portIsLive $portTag]} {
            continue
        }
        set port $::svvs::canvas_blocks::tagToPort($portTag)
        set direction [dict get $port direction]
        if {$direction eq "output"} {
            lappend outputs $portTag
        } elseif {$direction eq "input"} {
            lappend inputs $portTag
        }
    }

    if {[llength $outputs] == 0 || [llength $inputs] == 0} {
        ::svvs::console::log "Conexao automatica: adicione blocos com entradas e saidas ao diagrama." warn
        return 0
    }

    set occupiedInputs {}
    set existingPairs {}
    foreach id [array names connections] {
        set conn $connections($id)
        set from [dict get $conn from]
        set to [dict get $conn to]
        dict set occupiedInputs $to 1
        dict set existingPairs "$from|$to" 1
    }

    set created 0
    foreach inputTag $inputs {
        if {[dict exists $occupiedInputs $inputTag]} {
            continue
        }

        set inputPort $::svvs::canvas_blocks::tagToPort($inputTag)
        set inputName [string tolower [dict get $inputPort name]]
        set inputWidth [dict get $inputPort width]
        set inputBlock $::svvs::canvas_blocks::tagToBlock($inputTag)
        set inputCenter [::svvs::canvas_blocks::portCenter $inputTag]
        set bestOutput ""
        set bestDistance ""

        foreach outputTag $outputs {
            set outputPort $::svvs::canvas_blocks::tagToPort($outputTag)
            set outputBlock $::svvs::canvas_blocks::tagToBlock($outputTag)
            if {$outputBlock eq $inputBlock} {
                continue
            }
            if {[string tolower [dict get $outputPort name]] ne $inputName} {
                continue
            }
            if {[dict get $outputPort width] != $inputWidth} {
                continue
            }
            if {[dict exists $existingPairs "$outputTag|$inputTag"]} {
                continue
            }

            set outputCenter [::svvs::canvas_blocks::portCenter $outputTag]
            set dx [expr {[lindex $inputCenter 0] - [lindex $outputCenter 0]}]
            set dy [expr {[lindex $inputCenter 1] - [lindex $outputCenter 1]}]
            set distance [expr {($dx * $dx) + ($dy * $dy)}]
            if {$bestOutput eq "" || $distance < $bestDistance} {
                set bestOutput $outputTag
                set bestDistance $distance
            }
        }

        if {$bestOutput ne ""} {
            ::svvs::canvas_connections::drawConnection $bestOutput $inputTag $inputWidth
            dict set occupiedInputs $inputTag 1
            dict set existingPairs "$bestOutput|$inputTag" 1
            incr created
        }
    }

    if {$created == 0} {
        ::svvs::console::log "Conexao automatica: nenhuma entrada compativel e livre foi encontrada." warn
    } else {
        ::svvs::console::log "Conexao automatica concluida: $created conexao(oes) criada(s)." ok
    }
    return $created
}

proc ::svvs::canvas_connections::portIsLive {portTag} {
    set canvas $::svvs::canvas_blocks::canvas
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return 0
    }
    if {![info exists ::svvs::canvas_blocks::tagToPort($portTag)] ||
        ![info exists ::svvs::canvas_blocks::tagToBlock($portTag)]} {
        return 0
    }
    foreach item [$canvas find withtag $portTag] {
        if {[lsearch -exact [$canvas gettags $item] "port"] >= 0} {
            return 1
        }
    }
    return 0
}

proc ::svvs::canvas_connections::removeDangling {} {
    variable connections
    set canvas $::svvs::canvas_blocks::canvas
    foreach id [array names connections] {
        set conn $connections($id)
        if {![::svvs::canvas_connections::portIsLive [dict get $conn from]] ||
            ![::svvs::canvas_connections::portIsLive [dict get $conn to]]} {
            if {$canvas ne "" && [winfo exists $canvas]} {
                $canvas delete $id
            }
            unset connections($id)
        }
    }
}

proc ::svvs::canvas_connections::resolvePortTag {value} {
    if {[string match "port:*" $value]} {
        return $value
    }

    set parts [split $value .]
    if {[llength $parts] != 2} {
        return ""
    }

    set moduleName [lindex $parts 0]
    set portName [lindex $parts 1]
    foreach tag [array names ::svvs::canvas_blocks::tagToPort] {
        set info [::svvs::canvas_blocks::portInfo $tag]
        if {[dict get [dict get $info module] name] eq $moduleName && [dict get [dict get $info port] name] eq $portName} {
            return $tag
        }
    }
    return ""
}

proc ::svvs::canvas_connections::wireCoords {fromTag toTag {routeX1 ""} {routeY ""} {routeX2 ""}} {
    set a [::svvs::canvas_blocks::portCenter $fromTag]
    set b [::svvs::canvas_blocks::portCenter $toTag]
    set ax [lindex $a 0]
    set ay [lindex $a 1]
    set bx [lindex $b 0]
    set by [lindex $b 1]
    if {$routeX1 eq ""} {
        set routeX1 [expr {$ax + (($bx - $ax) / 3.0)}]
    }
    if {$routeX2 eq ""} {
        set routeX2 [expr {$ax + (2.0 * ($bx - $ax) / 3.0)}]
    }
    if {$routeY eq ""} {
        set routeY [expr {($ay + $by) / 2.0}]
    }
    return [list \
        $ax $ay \
        $routeX1 $ay \
        $routeX1 $routeY \
        $routeX2 $routeY \
        $routeX2 $by \
        $bx $by]
}

proc ::svvs::canvas_connections::updateGeometry {id} {
    variable connections
    set canvas $::svvs::canvas_blocks::canvas
    if {![info exists connections($id)] || $canvas eq "" || ![winfo exists $canvas]} {
        return
    }

    set conn $connections($id)
    set coords [::svvs::canvas_connections::wireCoords \
        [dict get $conn from] [dict get $conn to] \
        [dict get $conn routeX1] [dict get $conn routeY] [dict get $conn routeX2]]

    set handleCenters [dict create \
        source [list [lindex $coords 2] [expr {([lindex $coords 3] + [lindex $coords 5]) / 2.0}]] \
        middle [list [expr {([lindex $coords 4] + [lindex $coords 6]) / 2.0}] [lindex $coords 5]] \
        target [list [lindex $coords 6] [expr {([lindex $coords 7] + [lindex $coords 9]) / 2.0}]]]

    foreach item [$canvas find withtag $id] {
        set tags [$canvas gettags $item]
        if {[lsearch -exact $tags "connection-route-handle"] >= 0} {
            set handleTag [::svvs::canvas_connections::tagWithPrefix $tags "route-handle:"]
            set handle [lindex [split $handleTag :] 1]
            set center [dict get $handleCenters $handle]
            set midX [lindex $center 0]
            set midY [lindex $center 1]
            $canvas coords $item \
                [expr {$midX - 5}] [expr {$midY - 5}] \
                [expr {$midX + 5}] [expr {$midY + 5}]
        } else {
            $canvas coords $item {*}$coords
        }
        if {[lsearch -exact $tags "connection-hit"] >= 0} {
            $canvas lower $item
        }
    }
}

proc ::svvs::canvas_connections::refreshAll {} {
    variable connections
    set canvas $::svvs::canvas_blocks::canvas
    ::svvs::canvas_connections::removeDangling
    foreach id [array names connections] {
        if {![winfo exists $canvas]} {
            continue
        }
        ::svvs::canvas_connections::updateGeometry $id
    }
    ::svvs::canvas_connections::refreshDisplay
}

proc ::svvs::canvas_connections::toggleSimplified {} {
    variable simplifiedMode
    set simplifiedMode [expr {!$simplifiedMode}]
    ::svvs::layout::setToolbarActive "Simple Wires" $simplifiedMode
    ::svvs::canvas_connections::refreshDisplay
    if {$simplifiedMode} {
        ::svvs::console::log "Conexoes simplificadas visiveis."
    } else {
        ::svvs::console::log "Conexoes detalhadas visiveis."
    }
}

proc ::svvs::canvas_connections::refreshDisplay {} {
    variable simplifiedMode
    set canvas $::svvs::canvas_blocks::canvas
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return
    }

    set detailedState [expr {$simplifiedMode ? "hidden" : "normal"}]
    foreach tag {connection connection-hit} {
        foreach item [$canvas find withtag $tag] {
            $canvas itemconfigure $item -state $detailedState
        }
    }
    foreach item [$canvas find withtag connection-route-handle] {
        $canvas itemconfigure $item -state hidden
    }

    if {$simplifiedMode} {
        ::svvs::canvas_blocks::setSimplifiedBlockStyle 1
        $canvas delete wire-marker
        ::svvs::canvas_connections::rebuildSimplified
    } else {
        ::svvs::canvas_blocks::setSimplifiedBlockStyle 0
        ::svvs::canvas_blocks::updateTextForZoom
        $canvas delete simplified-connection
        ::svvs::canvas_connections::rebuildMarkers
        ::svvs::canvas_connections::paintSelection $::svvs::canvas_blocks::selectedTag
    }
}

proc ::svvs::canvas_connections::directedBlocks {conn} {
    set from [dict get $conn from]
    set to [dict get $conn to]
    set fromBlock $::svvs::canvas_blocks::tagToBlock($from)
    set toBlock $::svvs::canvas_blocks::tagToBlock($to)
    set fromDirection [dict get $::svvs::canvas_blocks::tagToPort($from) direction]
    set toDirection [dict get $::svvs::canvas_blocks::tagToPort($to) direction]
    if {$fromDirection eq "output"} {
        return [list $fromBlock $toBlock]
    }
    if {$toDirection eq "output"} {
        return [list $toBlock $fromBlock]
    }
    return [list $fromBlock $toBlock]
}

proc ::svvs::canvas_connections::blockBounds {id} {
    set canvas $::svvs::canvas_blocks::canvas
    foreach item [$canvas find withtag "block:$id"] {
        if {[lsearch -exact [$canvas gettags $item] "block-body"] >= 0} {
            return [$canvas coords $item]
        }
    }
    return ""
}

proc ::svvs::canvas_connections::blockEdgePoints {boundsA boundsB} {
    lassign $boundsA ax1 ay1 ax2 ay2
    lassign $boundsB bx1 by1 bx2 by2
    set acx [expr {($ax1 + $ax2) / 2.0}]
    set acy [expr {($ay1 + $ay2) / 2.0}]
    set bcx [expr {($bx1 + $bx2) / 2.0}]
    set bcy [expr {($by1 + $by2) / 2.0}]
    set dx [expr {$bcx - $acx}]
    set dy [expr {$bcy - $acy}]

    if {abs($dx) >= abs($dy)} {
        if {$dx >= 0} {
            return [list $ax2 $acy $bx1 $bcy]
        }
        return [list $ax1 $acy $bx2 $bcy]
    }
    if {$dy >= 0} {
        return [list $acx $ay2 $bcx $by1]
    }
    return [list $acx $ay1 $bcx $by2]
}

proc ::svvs::canvas_connections::normalizeSimpleRoute {route} {
    foreach {field default} {
        route1 "" routeMid "" route2 "" orientation "" sideA "" sideB ""
    } {
        if {![dict exists $route $field]} {
            dict set route $field $default
        }
    }
    if {[dict get $route orientation] eq "horizontal"} {
        dict set route orientation HH
    } elseif {[dict get $route orientation] eq "vertical"} {
        dict set route orientation VV
    }
    return $route
}

proc ::svvs::canvas_connections::automaticSides {boundsA boundsB} {
    lassign $boundsA ax1 ay1 ax2 ay2
    lassign $boundsB bx1 by1 bx2 by2
    set dx [expr {(($bx1 + $bx2) - ($ax1 + $ax2)) / 2.0}]
    set dy [expr {(($by1 + $by2) - ($ay1 + $ay2)) / 2.0}]
    if {abs($dx) >= abs($dy)} {
        return [expr {$dx >= 0 ? [list right left] : [list left right]}]
    }
    return [expr {$dy >= 0 ? [list bottom top] : [list top bottom]}]
}

proc ::svvs::canvas_connections::pointForSide {bounds side} {
    lassign $bounds x1 y1 x2 y2
    switch -- $side {
        left { return [list $x1 [expr {($y1 + $y2) / 2.0}]] }
        right { return [list $x2 [expr {($y1 + $y2) / 2.0}]] }
        top { return [list [expr {($x1 + $x2) / 2.0}] $y1] }
        bottom { return [list [expr {($x1 + $x2) / 2.0}] $y2] }
    }
}

proc ::svvs::canvas_connections::rebuildSimplified {} {
    variable connections
    variable simplifiedMode
    variable simplifiedRoutes
    variable selectedSimplePair
    set canvas $::svvs::canvas_blocks::canvas
    $canvas delete simplified-connection
    if {!$simplifiedMode} {
        return
    }

    foreach pair [array names simplifiedRoutes] {
        set simplifiedRoutes($pair) \
            [::svvs::canvas_connections::normalizeSimpleRoute $simplifiedRoutes($pair)]
    }

    array set pairs {}
    foreach id [array names connections] {
        lassign [::svvs::canvas_connections::directedBlocks $connections($id)] source target
        if {$source eq $target} {
            continue
        }
        set ordered [lsort [list $source $target]]
        set a [lindex $ordered 0]
        set b [lindex $ordered 1]
        set key "$a|$b"
        if {![info exists pairs($key)]} {
            set pairs($key) [dict create a $a b $b aToB 0 bToA 0]
        }
        if {$source eq $a} {
            dict set pairs($key) aToB 1
        } else {
            dict set pairs($key) bToA 1
        }
    }

    foreach key [lsort [array names pairs]] {
        set pair $pairs($key)
        set boundsA [::svvs::canvas_connections::blockBounds [dict get $pair a]]
        set boundsB [::svvs::canvas_connections::blockBounds [dict get $pair b]]
        if {$boundsA eq "" || $boundsB eq ""} {
            continue
        }
        set route [dict create route1 "" routeMid "" route2 "" orientation "" sideA "" sideB ""]
        if {[info exists simplifiedRoutes($key)]} {
            set route [::svvs::canvas_connections::normalizeSimpleRoute $simplifiedRoutes($key)]
        }
        set geometry [::svvs::canvas_connections::simplifiedGeometry $boundsA $boundsB $route]
        set coords [dict get $geometry coords]
        set displayRoute [dict get $geometry route]
        set displayOrientation [dict get $displayRoute orientation]
        if {[dict get $route orientation] ne "" &&
            [dict get $route orientation] ne $displayOrientation} {
            set savedSideA ""
            set savedSideB ""
            if {[dict exists $route sideA]} { set savedSideA [dict get $route sideA] }
            if {[dict exists $route sideB]} { set savedSideB [dict get $route sideB] }
            set route [dict create route1 "" routeMid "" route2 "" \
                orientation $displayOrientation sideA $savedSideA sideB $savedSideB]
        } else {
            dict set route orientation $displayOrientation
        }
        set simplifiedRoutes($key) $route
        if {[dict get $pair aToB] && [dict get $pair bToA]} {
            set arrow both
        } elseif {[dict get $pair aToB]} {
            set arrow last
        } else {
            set arrow first
        }
        $canvas create line {*}$coords \
            -fill [::svvs::theme::color bg] \
            -width 12 \
            -smooth false \
            -tags [list simplified-connection simplified-hit "simple-pair:$key"]
        $canvas create line {*}$coords \
            -fill [::svvs::theme::color wire] \
            -width 3 \
            -smooth false \
            -arrow $arrow \
            -arrowshape {10 12 5} \
            -tags [list simplified-connection simplified-wire "simple-pair:$key"]

        set handleCenters [dict get $geometry handles]
        foreach handle {source middle target} {
            if {![dict exists $handleCenters $handle]} {
                continue
            }
            lassign [dict get $handleCenters $handle] hx hy
            set state [expr {$key eq $selectedSimplePair ? "normal" : "hidden"}]
            $canvas create oval \
                [expr {$hx - 5}] [expr {$hy - 5}] [expr {$hx + 5}] [expr {$hy + 5}] \
                -fill [::svvs::theme::color accent] \
                -outline white \
                -width 1 \
                -state $state \
                -tags [list simplified-connection simplified-route-handle \
                    "simple-pair:$key" "simple-handle:$handle"]
        }
    }
    $canvas lower simplified-connection
    foreach item [$canvas find withtag simplified-route-handle] {
        if {[$canvas itemcget $item -state] eq "normal"} {
            $canvas raise $item
        }
    }
}

proc ::svvs::canvas_connections::simplifiedGeometry {boundsA boundsB route} {
    set route [::svvs::canvas_connections::normalizeSimpleRoute $route]
    lassign [::svvs::canvas_connections::automaticSides $boundsA $boundsB] autoA autoB
    set sideA [dict get $route sideA]
    set sideB [dict get $route sideB]
    if {$sideA eq ""} { set sideA $autoA }
    if {$sideB eq ""} { set sideB $autoB }
    lassign [::svvs::canvas_connections::pointForSide $boundsA $sideA] ax ay
    lassign [::svvs::canvas_connections::pointForSide $boundsB $sideB] bx by
    set axisA [expr {$sideA in {left right} ? "H" : "V"}]
    set axisB [expr {$sideB in {left right} ? "H" : "V"}]
    set orientation "$axisA$axisB"
    if {[dict get $route orientation] ne "" && [dict get $route orientation] ne $orientation} {
        set route [dict create route1 "" routeMid "" route2 "" orientation $orientation]
    }
    dict set route orientation $orientation

    set route1 [dict get $route route1]
    set routeMid [dict get $route routeMid]
    set route2 [dict get $route route2]
    if {$orientation eq "HH"} {
        if {$route1 eq ""} { set route1 [expr {$ax + (($bx - $ax) / 3.0)}] }
        if {$routeMid eq ""} { set routeMid [expr {($ay + $by) / 2.0}] }
        if {$route2 eq ""} { set route2 [expr {$ax + (2.0 * ($bx - $ax) / 3.0)}] }
        set coords [list $ax $ay $route1 $ay $route1 $routeMid \
            $route2 $routeMid $route2 $by $bx $by]
        set handles [dict create \
            source [list $route1 [expr {($ay + $routeMid) / 2.0}]] \
            middle [list [expr {($route1 + $route2) / 2.0}] $routeMid] \
            target [list $route2 [expr {($routeMid + $by) / 2.0}]]]
    } elseif {$orientation eq "VV"} {
        if {$route1 eq ""} { set route1 [expr {$ay + (($by - $ay) / 3.0)}] }
        if {$routeMid eq ""} { set routeMid [expr {($ax + $bx) / 2.0}] }
        if {$route2 eq ""} { set route2 [expr {$ay + (2.0 * ($by - $ay) / 3.0)}] }
        set coords [list $ax $ay $ax $route1 $routeMid $route1 \
            $routeMid $route2 $bx $route2 $bx $by]
        set handles [dict create \
            source [list [expr {($ax + $routeMid) / 2.0}] $route1] \
            middle [list $routeMid [expr {($route1 + $route2) / 2.0}]] \
            target [list [expr {($routeMid + $bx) / 2.0}] $route2]]
    } elseif {$orientation eq "HV"} {
        if {$route1 eq ""} { set route1 [expr {($ax + $bx) / 2.0}] }
        if {$routeMid eq ""} { set routeMid [expr {($ay + $by) / 2.0}] }
        set coords [list $ax $ay $route1 $ay $route1 $routeMid \
            $bx $routeMid $bx $by]
        set handles [dict create \
            source [list $route1 [expr {($ay + $routeMid) / 2.0}]] \
            middle [list [expr {($route1 + $bx) / 2.0}] $routeMid]]
    } else {
        if {$route1 eq ""} { set route1 [expr {($ay + $by) / 2.0}] }
        if {$routeMid eq ""} { set routeMid [expr {($ax + $bx) / 2.0}] }
        set coords [list $ax $ay $ax $route1 $routeMid $route1 \
            $routeMid $by $bx $by]
        set handles [dict create \
            source [list [expr {($ax + $routeMid) / 2.0}] $route1] \
            middle [list $routeMid [expr {($route1 + $by) / 2.0}]]]
    }
    dict set route route1 $route1
    dict set route routeMid $routeMid
    dict set route route2 $route2
    return [dict create coords $coords handles $handles route $route]
}

proc ::svvs::canvas_connections::segmentsFor {id} {
    variable connections
    set conn $connections($id)
    set coords [::svvs::canvas_connections::wireCoords \
        [dict get $conn from] [dict get $conn to] \
        [dict get $conn routeX1] [dict get $conn routeY] [dict get $conn routeX2]]
    set segments {}
    for {set i 0} {$i < [expr {[llength $coords] - 2}]} {incr i 2} {
        set x1 [lindex $coords $i]
        set y1 [lindex $coords [expr {$i + 1}]]
        set x2 [lindex $coords [expr {$i + 2}]]
        set y2 [lindex $coords [expr {$i + 3}]]
        if {$x1 == $x2 && $y1 == $y2} {
            continue
        }
        set orientation [expr {$y1 == $y2 ? "horizontal" : "vertical"}]
        lappend segments [dict create \
            id $id x1 $x1 y1 $y1 x2 $x2 y2 $y2 orientation $orientation]
    }
    return $segments
}

proc ::svvs::canvas_connections::strictlyBetween {value a b} {
    set low [expr {min($a, $b)}]
    set high [expr {max($a, $b)}]
    return [expr {$value > ($low + 2.0) && $value < ($high - 2.0)}]
}

proc ::svvs::canvas_connections::rebuildMarkers {} {
    variable connections
    variable simplifiedMode
    set canvas $::svvs::canvas_blocks::canvas
    if {$canvas eq "" || ![winfo exists $canvas]} {
        return
    }
    $canvas delete wire-marker
    if {$simplifiedMode} {
        return
    }

    set ids [lsort [array names connections]]
    set seenCrossings {}
    for {set a 0} {$a < [llength $ids]} {incr a} {
        set idA [lindex $ids $a]
        set segmentsA [::svvs::canvas_connections::segmentsFor $idA]
        for {set b [expr {$a + 1}]} {$b < [llength $ids]} {incr b} {
            set idB [lindex $ids $b]
            set segmentsB [::svvs::canvas_connections::segmentsFor $idB]
            foreach segmentA $segmentsA {
                foreach segmentB $segmentsB {
                    if {[dict get $segmentA orientation] eq [dict get $segmentB orientation]} {
                        continue
                    }
                    if {[dict get $segmentA orientation] eq "horizontal"} {
                        set horizontal $segmentA
                        set vertical $segmentB
                    } else {
                        set horizontal $segmentB
                        set vertical $segmentA
                    }
                    set x [dict get $vertical x1]
                    set y [dict get $horizontal y1]
                    if {![::svvs::canvas_connections::strictlyBetween \
                            $x [dict get $horizontal x1] [dict get $horizontal x2]] ||
                        ![::svvs::canvas_connections::strictlyBetween \
                            $y [dict get $vertical y1] [dict get $vertical y2]]} {
                        continue
                    }
                    set key "[format %.2f $x],[format %.2f $y]"
                    if {[dict exists $seenCrossings $key]} {
                        continue
                    }
                    dict set seenCrossings $key 1

                    set overId [dict get $horizontal id]
                    set overWidth [expr {[dict get $connections($overId) width] > 1 ? 3 : 2}]
                    set color [::svvs::theme::color wire]
                    if {$::svvs::canvas_blocks::selectedTag eq $overId} {
                        set color [::svvs::theme::color accent]
                        incr overWidth 2
                    }
                    $canvas create rectangle \
                        [expr {$x - 6}] [expr {$y - 6}] [expr {$x + 6}] [expr {$y + 6}] \
                        -fill [::svvs::theme::color bg] -outline "" \
                        -tags [list wire-marker crossing-gap]
                    $canvas create line [expr {$x - 7}] $y [expr {$x + 7}] $y \
                        -fill $color -width $overWidth \
                        -tags [list wire-marker crossing-over]
                }
            }
        }
    }

    array set endpointCount {}
    array set endpointCoords {}
    foreach id $ids {
        set conn $connections($id)
        foreach portTag [list [dict get $conn from] [dict get $conn to]] {
            set point [::svvs::canvas_blocks::portCenter $portTag]
            set key "[format %.2f [lindex $point 0]],[format %.2f [lindex $point 1]]"
            if {![info exists endpointCount($key)]} {
                set endpointCount($key) 0
                set endpointCoords($key) $point
            }
            incr endpointCount($key)
        }
    }
    foreach key [array names endpointCount] {
        if {$endpointCount($key) < 2} {
            continue
        }
        lassign $endpointCoords($key) x y
        $canvas create oval \
            [expr {$x - 4}] [expr {$y - 4}] [expr {$x + 4}] [expr {$y + 4}] \
            -fill [::svvs::theme::color text] \
            -outline [::svvs::theme::color bg] \
            -width 1 \
            -tags [list wire-marker connection-junction]
    }

    foreach item [$canvas find withtag connection-route-handle] {
        $canvas raise $item
    }
}

proc ::svvs::canvas_connections::tagWithPrefix {tags prefix} {
    foreach tag $tags {
        if {[string match "$prefix*" $tag]} {
            return $tag
        }
    }
    return ""
}

proc ::svvs::canvas_connections::beginRouteDragAt {id x y} {
    variable connections
    variable routeDragId
    variable routeDragField
    variable routeDragMoved
    set routeDragId ""
    set routeDragField ""
    set routeDragMoved 0
    if {[string match "simple:*" $id]} {
        ::svvs::canvas_connections::beginSimpleRouteDragAt [string range $id 7 end] $x $y
        return
    }
    if {![info exists connections($id)]} {
        return
    }

    set canvas $::svvs::canvas_blocks::canvas
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]
    set handleTag ""
    foreach item [lreverse [$canvas find overlapping \
        [expr {$cx - 7}] [expr {$cy - 7}] [expr {$cx + 7}] [expr {$cy + 7}]]] {
        set tags [$canvas gettags $item]
        if {[lsearch -exact $tags $id] < 0 ||
            [lsearch -exact $tags "connection-route-handle"] < 0} {
            continue
        }
        set handleTag [::svvs::canvas_connections::tagWithPrefix $tags "route-handle:"]
        break
    }
    switch -- $handleTag {
        "route-handle:source" { set routeDragField routeX1 }
        "route-handle:middle" { set routeDragField routeY }
        "route-handle:target" { set routeDragField routeX2 }
        default { return }
    }
    set routeDragId $id
}

proc ::svvs::canvas_connections::beginSimpleRouteDragAt {pair x y} {
    variable simpleDragPair
    variable simpleDragField
    set simpleDragPair ""
    set simpleDragField ""
    set canvas $::svvs::canvas_blocks::canvas
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]
    foreach item [lreverse [$canvas find overlapping \
        [expr {$cx - 7}] [expr {$cy - 7}] [expr {$cx + 7}] [expr {$cy + 7}]]] {
        set tags [$canvas gettags $item]
        if {[lsearch -exact $tags "simple-pair:$pair"] < 0 ||
            [lsearch -exact $tags simplified-route-handle] < 0} {
            continue
        }
        set handleTag [::svvs::canvas_connections::tagWithPrefix $tags "simple-handle:"]
        switch -- $handleTag {
            "simple-handle:source" { set simpleDragField route1 }
            "simple-handle:middle" { set simpleDragField routeMid }
            "simple-handle:target" { set simpleDragField route2 }
        }
        ::svvs::canvas_connections::materializeSimpleRoute $pair
        set simpleDragPair $pair
        return
    }
}

proc ::svvs::canvas_connections::materializeSimpleRoute {pair} {
    variable simplifiedRoutes
    if {![info exists simplifiedRoutes($pair)]} {
        return
    }
    lassign [split $pair |] a b
    set boundsA [::svvs::canvas_connections::blockBounds $a]
    set boundsB [::svvs::canvas_connections::blockBounds $b]
    if {$boundsA eq "" || $boundsB eq ""} {
        return
    }
    set geometry [::svvs::canvas_connections::simplifiedGeometry \
        $boundsA $boundsB $simplifiedRoutes($pair)]
    set simplifiedRoutes($pair) [dict get $geometry route]
}

proc ::svvs::canvas_connections::dragRouteTo {screenX screenY} {
    variable connections
    variable routeDragId
    variable routeDragField
    variable routeDragMoved
    variable simpleDragPair
    variable simpleDragField
    variable simplifiedRoutes
    set canvas $::svvs::canvas_blocks::canvas
    if {$simpleDragPair ne "" && $simpleDragField ne "" &&
        [info exists simplifiedRoutes($simpleDragPair)]} {
        set route [::svvs::canvas_connections::normalizeSimpleRoute \
            $simplifiedRoutes($simpleDragPair)]
        set orientation [dict get $route orientation]
        set startsHorizontal [string match "H*" $orientation]
        if {($startsHorizontal && $simpleDragField eq "routeMid") ||
            (!$startsHorizontal && $simpleDragField ne "routeMid")} {
            dict set route $simpleDragField [$canvas canvasy $screenY]
        } else {
            dict set route $simpleDragField [$canvas canvasx $screenX]
        }
        set simplifiedRoutes($simpleDragPair) $route
        set routeDragMoved 1
        ::svvs::canvas_connections::rebuildSimplified
        return 1
    }
    if {$routeDragId eq "" || $routeDragField eq "" || ![info exists connections($routeDragId)]} {
        return 0
    }

    ::svvs::canvas_connections::materializeRoute $routeDragId
    if {$routeDragField eq "routeY"} {
        dict set connections($routeDragId) $routeDragField [$canvas canvasy $screenY]
    } else {
        dict set connections($routeDragId) $routeDragField [$canvas canvasx $screenX]
    }
    set routeDragMoved 1
    ::svvs::canvas_connections::updateGeometry $routeDragId
    ::svvs::canvas_connections::refreshDisplay
    return 1
}

proc ::svvs::canvas_connections::materializeRoute {id} {
    variable connections
    set conn $connections($id)
    set coords [::svvs::canvas_connections::wireCoords \
        [dict get $conn from] [dict get $conn to] \
        [dict get $conn routeX1] [dict get $conn routeY] [dict get $conn routeX2]]
    if {[dict get $conn routeX1] eq ""} {
        dict set connections($id) routeX1 [lindex $coords 2]
    }
    if {[dict get $conn routeY] eq ""} {
        dict set connections($id) routeY [lindex $coords 5]
    }
    if {[dict get $conn routeX2] eq ""} {
        dict set connections($id) routeX2 [lindex $coords 6]
    }
}

proc ::svvs::canvas_connections::endRouteDrag {} {
    variable routeDragId
    variable routeDragField
    variable routeDragMoved
    variable simpleDragPair
    variable simpleDragField
    if {$routeDragMoved} {
        ::svvs::console::log "Rota da conexao ajustada."
    }
    set routeDragId ""
    set routeDragField ""
    set routeDragMoved 0
    set simpleDragPair ""
    set simpleDragField ""
}

proc ::svvs::canvas_connections::scaleRoutes {centerX centerY factor} {
    variable connections
    variable simplifiedRoutes
    foreach id [array names connections] {
        foreach field {routeX1 routeX2} {
            set value [dict get $connections($id) $field]
            if {$value ne ""} {
                dict set connections($id) $field \
                    [expr {$centerX + (($value - $centerX) * $factor)}]
            }
        }
        set value [dict get $connections($id) routeY]
        if {$value ne ""} {
            dict set connections($id) routeY \
                [expr {$centerY + (($value - $centerY) * $factor)}]
        }
    }
    foreach pair [array names simplifiedRoutes] {
        set route [::svvs::canvas_connections::normalizeSimpleRoute $simplifiedRoutes($pair)]
        set orientation [dict get $route orientation]
        foreach field {route1 routeMid route2} {
            set value [dict get $route $field]
            if {$value eq ""} {
                continue
            }
            set startsHorizontal [string match "H*" $orientation]
            set usesY [expr {
                ($startsHorizontal && $field eq "routeMid") ||
                (!$startsHorizontal && $field ne "routeMid")}]
            if {$usesY} {
                dict set route $field [expr {$centerY + (($value - $centerY) * $factor)}]
            } else {
                dict set route $field [expr {$centerX + (($value - $centerX) * $factor)}]
            }
        }
        set simplifiedRoutes($pair) $route
    }
}

proc ::svvs::canvas_connections::portLabel {portTag} {
    set info [::svvs::canvas_blocks::portInfo $portTag]
    return "[dict get [dict get $info module] name].[dict get [dict get $info port] name]"
}

proc ::svvs::canvas_connections::signalName {portTag} {
    set info [::svvs::canvas_blocks::portInfo $portTag]
    return [dict get [dict get $info port] name]
}

proc ::svvs::canvas_connections::connectionWidth {fromTag toTag} {
    set a [dict get [::svvs::canvas_blocks::portInfo $fromTag] port]
    set b [dict get [::svvs::canvas_blocks::portInfo $toTag] port]
    return [expr {max([dict get $a width], [dict get $b width])}]
}

proc ::svvs::canvas_connections::selectAt {x y} {
    variable connections
    variable simplifiedMode
    set canvas $::svvs::canvas_blocks::canvas
    set item [::svvs::canvas_connections::itemAt $x $y]
    if {$item eq ""} {
        return 0
    }
    set tags [$canvas gettags $item]
    if {$simplifiedMode} {
        set pairTag [::svvs::canvas_connections::tagWithPrefix $tags "simple-pair:"]
        if {$pairTag ne ""} {
            ::svvs::canvas_connections::selectSimplePair [string range $pairTag 12 end]
            return 1
        }
    }
    foreach tag $tags {
        if {[string match "conn:*" $tag] && [info exists connections($tag)]} {
            ::svvs::canvas_connections::select $tag
            return 1
        }
    }
    return 0
}

proc ::svvs::canvas_connections::itemAt {x y} {
    set canvas $::svvs::canvas_blocks::canvas
    set cx [$canvas canvasx $x]
    set cy [$canvas canvasy $y]
    foreach item [lreverse [$canvas find overlapping [expr {$cx - 6}] [expr {$cy - 6}] [expr {$cx + 6}] [expr {$cy + 6}]]] {
        set tags [$canvas gettags $item]
        if {[lsearch -exact $tags "connection"] >= 0 ||
            [lsearch -exact $tags "connection-hit"] >= 0 ||
            [lsearch -exact $tags "connection-route-handle"] >= 0 ||
            [lsearch -exact $tags "simplified-wire"] >= 0 ||
            [lsearch -exact $tags "simplified-hit"] >= 0 ||
            [lsearch -exact $tags "simplified-route-handle"] >= 0} {
            return $item
        }
    }
    return ""
}

proc ::svvs::canvas_connections::selectSimplePair {pair} {
    variable selectedSimplePair
    set selectedSimplePair $pair
    set ::svvs::canvas_blocks::selectedTag "simple:$pair"
    ::svvs::canvas_connections::rebuildSimplified
    ::svvs::properties_panel::showWelcome
    ::svvs::console::log "Conexao simplificada selecionada."
}

proc ::svvs::canvas_connections::showSimplifiedSideMenu {rootX rootY x y} {
    if {[::svvs::simulation_components::rightClick $rootX $rootY $x $y]} {
        return
    }
    variable simplifiedMode
    if {!$simplifiedMode} {
        return
    }
    set item [::svvs::canvas_connections::itemAt $x $y]
    if {$item eq ""} {
        return
    }
    set tags [$::svvs::canvas_blocks::canvas gettags $item]
    set pairTag [::svvs::canvas_connections::tagWithPrefix $tags "simple-pair:"]
    if {$pairTag eq ""} {
        return
    }
    set pair [string range $pairTag 12 end]
    lassign [split $pair |] a b
    set nameA [dict get [dict get $::svvs::canvas_blocks::blocks($a) module] name]
    set nameB [dict get [dict get $::svvs::canvas_blocks::blocks($b) module] name]

    catch {destroy .simpleWireMenu}
    menu .simpleWireMenu -tearoff 0 \
        -background [::svvs::theme::color panel] \
        -foreground [::svvs::theme::color text] \
        -activebackground [::svvs::theme::color selected] \
        -activeforeground white
    menu .simpleWireMenu.sideA -tearoff 0
    menu .simpleWireMenu.sideB -tearoff 0
    foreach {label side} {Left left Right right Top top Bottom bottom} {
        .simpleWireMenu.sideA add command -label $label \
            -command [list ::svvs::canvas_connections::setSimplifiedSide $pair sideA $side]
        .simpleWireMenu.sideB add command -label $label \
            -command [list ::svvs::canvas_connections::setSimplifiedSide $pair sideB $side]
    }
    .simpleWireMenu add cascade -label "$nameA side" -menu .simpleWireMenu.sideA
    .simpleWireMenu add cascade -label "$nameB side" -menu .simpleWireMenu.sideB
    ::svvs::canvas_connections::selectSimplePair $pair
    tk_popup .simpleWireMenu $rootX $rootY
}

proc ::svvs::canvas_connections::setSimplifiedSide {pair field side} {
    variable simplifiedRoutes
    variable selectedSimplePair
    if {![info exists simplifiedRoutes($pair)]} {
        return
    }
    set route [::svvs::canvas_connections::normalizeSimpleRoute $simplifiedRoutes($pair)]
    dict set route $field $side
    dict set route route1 ""
    dict set route routeMid ""
    dict set route route2 ""
    dict set route orientation ""
    set simplifiedRoutes($pair) $route
    set selectedSimplePair $pair
    set ::svvs::canvas_blocks::selectedTag "simple:$pair"
    ::svvs::canvas_connections::rebuildSimplified
    ::svvs::console::log "Lado da conexao simplificada alterado."
}

proc ::svvs::canvas_connections::select {connTag} {
    variable connections
    set canvas $::svvs::canvas_blocks::canvas
    if {![info exists connections($connTag)]} {
        return
    }

    set ::svvs::canvas_blocks::selectedTag $connTag
    ::svvs::canvas_blocks::paintSelection
    ::svvs::properties_panel::showConnection [dict create \
        signal [dict get $connections($connTag) signal] \
        from [::svvs::canvas_connections::portLabel [dict get $connections($connTag) from]] \
        to [::svvs::canvas_connections::portLabel [dict get $connections($connTag) to]] \
        width [dict get $connections($connTag) width]]
    foreach item [$canvas find withtag $connTag] {
        set tags [$canvas gettags $item]
        if {[lsearch -exact $tags "connection"] >= 0} {
            $canvas raise $item
        } elseif {[lsearch -exact $tags "connection-hit"] >= 0} {
            $canvas lower $item
        }
    }
    ::svvs::canvas_connections::rebuildMarkers
    foreach item [$canvas find withtag $connTag] {
        if {[lsearch -exact [$canvas gettags $item] "connection-route-handle"] >= 0} {
            $canvas raise $item
        }
    }
    ::svvs::console::log "Conexao selecionada."
}

proc ::svvs::canvas_connections::paintSelection {{selected ""}} {
    variable connections
    variable simplifiedMode
    variable selectedSimplePair
    set canvas $::svvs::canvas_blocks::canvas
    if {![string match "simple:*" $selected]} {
        set selectedSimplePair ""
    }
    foreach id [array names connections] {
        if {[llength [$canvas find withtag $id]] == 0} {
            continue
        }
        set conn $connections($id)
        set normalWidth [expr {[dict get $conn width] > 1 ? 3 : 2}]
        set color [::svvs::theme::color wire]
        set drawWidth $normalWidth
        if {$id eq $selected} {
            set color [::svvs::theme::color accent]
            set drawWidth [expr {$normalWidth + 2}]
        }
        foreach item [$canvas find withtag $id] {
            set tags [$canvas gettags $item]
            if {[lsearch -exact $tags "connection"] >= 0} {
                $canvas itemconfigure $item -fill $color -width $drawWidth
            } elseif {[lsearch -exact $tags "connection-route-handle"] >= 0} {
                $canvas itemconfigure $item -state [expr {!$simplifiedMode && $id eq $selected ? "normal" : "hidden"}]
                if {!$simplifiedMode && $id eq $selected} {
                    $canvas raise $item
                }
            }
        }
    }
    if {!$simplifiedMode} {
        ::svvs::canvas_connections::rebuildMarkers
    } else {
        ::svvs::canvas_connections::rebuildSimplified
    }
}

proc ::svvs::canvas_connections::remove {connTag} {
    variable connections
    catch {unset connections($connTag)}
    ::svvs::canvas_connections::refreshDisplay
}

proc ::svvs::canvas_connections::removeForBlock {blockTag} {
    variable connections
    variable simplifiedRoutes
    set blockId [lindex [split $blockTag :] 1]
    foreach id [array names connections] {
        set conn $connections($id)
        if {[string match "port:$blockId:*" [dict get $conn from]] || [string match "port:$blockId:*" [dict get $conn to]]} {
            catch {$::svvs::canvas_blocks::canvas delete $id}
            unset connections($id)
        }
    }
    foreach pair [array names simplifiedRoutes] {
        if {[lsearch -exact [split $pair |] $blockId] >= 0} {
            unset simplifiedRoutes($pair)
        }
    }
    ::svvs::canvas_connections::refreshDisplay
}

proc ::svvs::canvas_connections::exportSimplifiedRoutes {} {
    variable simplifiedRoutes
    set result {}
    foreach pair [lsort [array names simplifiedRoutes]] {
        set route [::svvs::canvas_connections::normalizeSimpleRoute $simplifiedRoutes($pair)]
        set simplifiedRoutes($pair) $route
        lappend result [dict create pair $pair route $route]
    }
    return $result
}

proc ::svvs::canvas_connections::importSimplifiedRoutes {items} {
    variable simplifiedRoutes
    array unset simplifiedRoutes
    array set simplifiedRoutes {}
    foreach item $items {
        if {[dict exists $item pair] && [dict exists $item route]} {
            set route [::svvs::canvas_connections::normalizeSimpleRoute [dict get $item route]]
            set simplifiedRoutes([dict get $item pair]) $route
        }
    }
}

proc ::svvs::canvas_connections::cancel {} {
    variable pendingPort
    variable routeDragId
    variable routeDragField
    variable routeDragMoved
    variable simpleDragPair
    variable simpleDragField
    set pendingPort ""
    set routeDragId ""
    set routeDragField ""
    set routeDragMoved 0
    set simpleDragPair ""
    set simpleDragField ""
}

proc ::svvs::canvas_connections::clearAll {} {
    variable connections
    variable pendingPort
    variable routeDragId
    variable routeDragField
    variable routeDragMoved
    variable simplifiedMode
    variable simplifiedRoutes
    variable selectedSimplePair
    variable simpleDragPair
    variable simpleDragField
    variable seq
    array unset connections
    array set connections {}
    set pendingPort ""
    set routeDragId ""
    set routeDragField ""
    set routeDragMoved 0
    set simplifiedMode 0
    ::svvs::layout::setToolbarActive "Simple Wires" 0
    array unset simplifiedRoutes
    array set simplifiedRoutes {}
    set selectedSimplePair ""
    set simpleDragPair ""
    set simpleDragField ""
    set seq 0
    if {$::svvs::canvas_blocks::canvas ne "" && [winfo exists $::svvs::canvas_blocks::canvas]} {
        $::svvs::canvas_blocks::canvas delete wire-marker
        $::svvs::canvas_blocks::canvas delete simplified-connection
    }
}

proc ::svvs::canvas_connections::exportConnectionData {} {
    variable connections

    set exported {}
    foreach id [lsort [array names connections]] {
        set conn $connections($id)
        lappend exported [dict create \
            id $id \
            from [dict get $conn from] \
            to [dict get $conn to] \
            signal [dict get $conn signal] \
            width [dict get $conn width] \
            routeX1 [dict get $conn routeX1] \
            routeY [dict get $conn routeY] \
            routeX2 [dict get $conn routeX2]]
    }
    return $exported
}

proc ::svvs::canvas_connections::importConnectionData {items} {
    variable connections
    variable seq
    foreach conn $items {
        if {![dict exists $conn from] || ![dict exists $conn to]} {
            continue
        }
        set id "conn:[incr seq]"
        if {[dict exists $conn id]} {
            set id [dict get $conn id]
        }
        set from [dict get $conn from]
        set to [dict get $conn to]
        set width 1
        if {[dict exists $conn width]} {
            set width [dict get $conn width]
        }
        set routeX1 ""
        set routeY ""
        set routeX2 ""
        if {[dict exists $conn routeX1]} {
            set routeX1 [dict get $conn routeX1]
        }
        if {[dict exists $conn routeY]} {
            set routeY [dict get $conn routeY]
        }
        if {[dict exists $conn routeX2]} {
            set routeX2 [dict get $conn routeX2]
        }
        if {[dict exists $conn routeX]} {
            set routeX1 [dict get $conn routeX]
            set routeX2 [dict get $conn routeX]
        }
        if {[info exists ::svvs::canvas_blocks::tagToPort($from)] && [info exists ::svvs::canvas_blocks::tagToPort($to)]} {
            ::svvs::canvas_connections::drawConnectionWithId $id $from $to $width $routeX1 $routeY $routeX2
            if {[dict exists $conn signal]} {
                dict set connections($id) signal [dict get $conn signal]
            }
        }
    }
}
