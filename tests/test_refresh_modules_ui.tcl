set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "$message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]
wm withdraw .

proc testRefresh {} {
    set directory [file join $::root .rtl_explorer_build refresh_[pid]]
    file mkdir $directory
    set path [file join $directory demo.sv]
    set handle [open $path w]
    puts $handle {module demo(input a, b, output q); assign q = a & b; endmodule}
    close $handle
    ::svvs::layout::openFolderPath $directory
    set module [lindex $::svvs::project_tree::sampleModules 0]
    dict set module instance custom_instance
    set id [::svvs::canvas_blocks::drawBlock $module 300 180]
    set ::svvs::canvas_blocks::selectedTag "block:$id"
    ::svvs::simulation_components::autoIoForSelected both
    set before [::svvs::canvas_blocks::exportDiagramData]
    set nodeCount [llength [dict get $before nodes]]
    set connectionCount [array size ::svvs::canvas_connections::connections]
    set handle [open $path w]
    puts $handle {module demo(input a, input [1:0] b, input c, output q); assign q = a & b[0] & c; endmodule}
    close $handle
    if {![::svvs::project_tree::refreshModules]} { error "Refresh failed" }
    set after [::svvs::canvas_blocks::exportDiagramData]
    if {[llength [dict get $after nodes]] != $nodeCount} { error "Refresh lost diagram blocks" }
    set updated [dict get $::svvs::canvas_blocks::blocks($id) module]
    if {[dict get $updated instance] ne "custom_instance"} { error "Instance name lost" }
    set widths {}
    foreach port [dict get $updated ports] { dict set widths [dict get $port name] [dict get $port width] }
    if {[dict get $widths b] != 2 || ![dict exists $widths c]} { error "Ports not refreshed: $widths" }
    if {[array size ::svvs::canvas_connections::connections] != $connectionCount - 1} {
        error "Compatible connections were not preserved"
    }
    foreach old [dict get $before nodes] new [dict get $after nodes] {
        foreach key {id x y width height} {
            if {[dict get $old $key] ne [dict get $new $key]} { error "Layout changed: $key" }
        }
    }
    if {[bind . <F5>] eq ""} { error "Refresh shortcut missing" }
    if {![::svvs::project_tree::refreshModules]} { error "Second refresh failed" }
    set handle [open [file join $directory new.v] w]
    puts $handle {module newly_added(input clk); endmodule}
    close $handle
    if {![::svvs::project_tree::refreshModules]} { error "Folder refresh failed" }
    if {[::svvs::project_tree::moduleByName newly_added] eq ""} { error "New file not detected" }
    set saved [::svvs::project_tree::exportProjectData]
    if {[dict get $saved directory] ne [file normalize $directory]} { error "Folder not saved" }
    set projectPath [file join $directory demo.rtlex]
    if {![::svvs::layout::saveProjectTo $projectPath]} { error "Project save failed" }
    set relocated "${directory}_moved"
    file copy $directory $relocated
    if {![::svvs::layout::openProjectFrom [file join $relocated demo.rtlex]]} {
        error "Relocated project did not open"
    }
    set expected [file normalize [file join $relocated demo.sv]]
    if {[dict get $::svvs::canvas_blocks::blocks($id) module sourcePath] ne $expected} {
        error "Diagram kept original source path"
    }
    if {![::svvs::project_tree::refreshModules]} { error "Refresh after relocation failed" }
    puts "refresh modules UI tests: ok"
    destroy .
    set ::testDone 1
}
after 100 testRefresh
vwait ::testDone
