set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "$message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]
proc assertHiddenWires {} {
    set canvas $::svvs::canvas_blocks::canvas
    foreach tag {connection connection-hit connection-range-label connection-route-handle simplified-connection simplified-wire simplified-hit simplified-route-handle wire-marker} {
        foreach item [$canvas find withtag $tag] {
            if {[$canvas itemcget $item -state] ne "hidden"} {
                error "Wire artifact became visible while Wires was off: $tag ([$canvas gettags $item])"
            }
        }
    }
}
proc testHiddenWires {} {
    set source [::svvs::canvas_blocks::drawBlock [::svvs::simulation_components::templateByKind input] 80 100]
    set a [::svvs::canvas_blocks::drawBlock [::svvs::simulation_components::templateByKind led] 350 80]
    set b [::svvs::canvas_blocks::drawBlock [::svvs::simulation_components::templateByKind led] 350 220]
    set conn [::svvs::canvas_connections::drawConnection "port:$source:out" "port:$a:in"]
    ::svvs::canvas_connections::drawConnection "port:$source:out" "port:$b:in"
    foreach simple {0 1} {
        set ::svvs::canvas_connections::simplifiedMode $simple
        set ::svvs::canvas_connections::wiresVisible 1
        ::svvs::canvas_connections::refreshDisplay
        ::svvs::canvas_connections::toggleWires
        assertHiddenWires
        foreach selected [list "block:$source" "block:$a" "port:$source:out" $conn ""] {
            set ::svvs::canvas_blocks::selectedTag $selected
            ::svvs::canvas_blocks::paintSelection
            assertHiddenWires
        }
        ::svvs::canvas_connections::select $conn
        assertHiddenWires
        ::svvs::canvas_connections::rebuildMarkers
        ::svvs::canvas_connections::rebuildSimplified
        assertHiddenWires
        ::svvs::canvas_connections::refreshAll
        update
        assertHiddenWires
        ::svvs::canvas_connections::toggleWires
        set visible 0
        set canvas $::svvs::canvas_blocks::canvas
        foreach item [$canvas find withtag [expr {$simple ? "simplified-wire" : "connection"}]] {
            if {[$canvas itemcget $item -state] ne "hidden"} { set visible 1 }
        }
        if {!$visible} { error "Wires did not return after enabling Wires" }
    }
}
if {[catch {testHiddenWires} message options]} {
    puts stderr [dict get $options -errorinfo]
    exit 1
}
puts "Wire visibility regression: ok"
destroy .
exit 0
