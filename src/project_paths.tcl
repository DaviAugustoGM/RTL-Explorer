namespace eval ::svvs::project_paths {}

proc ::svvs::project_paths::relative {base path} {
    if {$path eq ""} { return "" }
    set baseParts [file split [file normalize $base]]
    set pathParts [file split [file normalize $path]]
    set common 0
    foreach a $baseParts b $pathParts {
        if {$a eq "" || $b eq ""} { break }
        if {$::tcl_platform(platform) eq "windows"} {
            if {![string equal -nocase $a $b]} { break }
        } elseif {$a ne $b} { break }
        incr common
    }
    if {$common == 0} { return [file normalize $path] }
    set parts [concat [lrepeat [expr {[llength $baseParts] - $common}] ..] [lrange $pathParts $common end]]
    if {![llength $parts]} { return . }
    return [join $parts /]
}

proc ::svvs::project_paths::resolve {base path {directory 0}} {
    if {$path eq ""} { return "" }
    set portable [string map {\\ /} $path]
    set absolute [expr {[file pathtype $portable] ne "relative" || [regexp {^[A-Za-z]:/} $portable]}]
    set candidates {}
    if {!$absolute} {
        lappend candidates [file join $base $portable]
    } else {
        # Legacy absolute paths can belong to another OS or an old project location.
        set parts [split [string trimleft $portable /] /]
        set first [expr {[regexp {^[A-Za-z]:$} [lindex $parts 0]] ? 1 : 0}]
        for {set i $first} {$i < [llength $parts]} {incr i} {
            lappend candidates [file join $base {*}[lrange $parts $i end]]
        }
        lappend candidates $portable
    }
    foreach candidate $candidates {
        if {($directory && [file isdirectory $candidate]) || (!$directory && [file isfile $candidate])} {
            return [file normalize $candidate]
        }
    }
    if {$directory} { return [file normalize $base] }
    error "Arquivo de design nao encontrado: $path (pasta do projeto: $base)"
}

proc ::svvs::project_paths::convert {data projectPath mode} {
    set base [file dirname [file normalize $projectPath]]
    set command ::svvs::project_paths::$mode
    set mapping {}
    if {[dict exists $data project files]} {
        set files {}
        foreach path [dict get $data project files] {
            set converted [$command $base $path]
            dict set mapping $path $converted
            lappend files $converted
        }
        dict set data project files $files
    }
    if {[dict exists $data project directory]} {
        set path [dict get $data project directory]
        if {$mode eq "resolve"} {
            set originalRoot [string trimright [string map {\\ /} $path] /]
            set path [$command $base $path 1]
            dict for {original resolved} $mapping {
                set original [string map {\\ /} $original]
                if {$originalRoot ne "" && [string first "$originalRoot/" $original] == 0 &&
                    $original ne $resolved} {
                    set suffix [string range $original [expr {[string length $originalRoot] + 1}] end]
                    set relocated $resolved
                    foreach part [split $suffix /] { set relocated [file dirname $relocated] }
                    set path $relocated
                    break
                }
            }
        } else {
            set path [$command $base $path]
        }
        dict set data project directory $path
    }
    foreach location {{project modules} {project fsms} {diagram nodes}} key {sourcePath file sourcePath} {
        if {![dict exists $data {*}$location]} { continue }
        set items {}
        foreach item [dict get $data {*}$location] {
            set keys [list $key]
            if {$location eq {diagram nodes}} { set keys [list module $key] }
            if {[dict exists $item {*}$keys]} {
                set path [dict get $item {*}$keys]
                if {![dict exists $mapping $path]} { dict set mapping $path [$command $base $path] }
                dict set item {*}$keys [dict get $mapping $path]
            }
            lappend items $item
        }
        dict set data {*}$location $items
    }
    return $data
}
