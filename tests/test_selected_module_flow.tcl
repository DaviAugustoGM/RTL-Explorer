if {[llength $argv] != 2} {
    error "usage: test_selected_module_flow.tcl SOURCE_FOLDER MODULE"
}
set root [file dirname [file dirname [file normalize [info script]]]]
set ::APP_DIR [file join $root src]
namespace eval ::svvs::canvas_blocks { variable blocks; array set blocks {} }
namespace eval ::svvs::canvas_connections {}
namespace eval ::svvs::project_tree { variable projectFiles {} }
proc ::svvs::canvas_connections::exportConnectionData {} { return {} }
source [file join $root src sv_parser.tcl]
source [file join $root src simulation_components.tcl]
source [file join $root src simulation_model.tcl]

lassign $argv folder requestedModule
set ::svvs::project_tree::projectFiles [glob -nocomplain -directory $folder *.sv]
set modules [::svvs::sv_parser::parseModulesFromFiles $::svvs::project_tree::projectFiles]
set selected ""
foreach module $modules {
    if {[dict get $module name] eq $requestedModule} {
        set selected $module
        break
    }
}
if {$selected eq ""} { error "module not found: $requestedModule" }
set ::svvs::canvas_blocks::blocks(selected) [dict create module $selected]
set result [::svvs::simulation_model::prepare]
if {![dict get $result ok]} { error [dict get $result message] }
puts "selected module flow test: ok ($requestedModule)"
