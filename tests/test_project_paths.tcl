set root [file dirname [file dirname [file normalize [info script]]]]
source [file join $root src project_paths.tcl]
set base [file join $root .rtl_explorer_build paths_[pid]]
set original [file join $base original]
set moved [file join $base moved]
file mkdir [file join $original rtl]
set source [file join $original rtl top.sv]
set handle [open $source w]; puts $handle {module top; endmodule}; close $handle
set data [dict create project [dict create files [list $source] directory $original \
    modules [list [dict create name top sourcePath $source]] \
    fsms [list [dict create file $source]]] \
    diagram [dict create nodes [list [dict create module [dict create name top sourcePath $source]]]]]
set portable [::svvs::project_paths::convert $data [file join $original design.rtlex] relative]
if {[dict get $portable project files] ne {rtl/top.sv}} { error "Source not relative: $portable" }
if {[dict get $portable project directory] ne "."} { error "Root not relative" }
file copy $original $moved
set reopened [::svvs::project_paths::convert $portable [file join $moved design.rtlex] resolve]
set expected [file normalize [file join $moved rtl top.sv]]
foreach source [concat [dict get $reopened project files] \
    [list [dict get [lindex [dict get $reopened project modules] 0] sourcePath]] \
    [list [dict get [lindex [dict get $reopened project fsms] 0] file]] \
    [list [dict get [lindex [dict get $reopened diagram nodes] 0] module sourcePath]]] {
    if {$source ne $expected} { error "Relocation failed: $source" }
}
set legacy [::svvs::project_paths::convert $data [file join $moved old.rtlex] resolve]
if {[dict get $legacy project files] ne [list $expected] ||
    [dict get $legacy project directory] ne [file normalize $moved]} { error "Legacy project used original location" }
foreach foreign {{C:\Users\someone\project\rtl\top.sv} /home/student/project/rtl/top.sv} {
    if {[::svvs::project_paths::resolve $moved $foreign] ne $expected} { error "Foreign path not resolved" }
}
if {![catch {::svvs::project_paths::resolve $moved missing.sv}]} { error "Missing file silently accepted" }
puts "project path tests: ok"
