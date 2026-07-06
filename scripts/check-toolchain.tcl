set ::APP_DIR [file normalize [file join [file dirname [info script]] .. src]]
source [file join $::APP_DIR toolchain.tcl]
::svvs::toolchain::activate

set missing {}
foreach {name value} [::svvs::toolchain::summary] {
    puts [format "%-10s %s" $name [expr {$value eq "" ? "NOT FOUND" : $value}]]
    if {$value eq ""} { lappend missing $name }
}
if {[llength $missing] > 0} {
    puts stderr "Missing tools: [join $missing {, }]"
    exit 1
}
puts "RTL Explorer toolchain is ready."
