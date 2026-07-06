namespace eval ::svvs::toolchain {
    variable activated 0
}

proc ::svvs::toolchain::appRoot {} {
    return [file dirname [file normalize $::APP_DIR]]
}

proc ::svvs::toolchain::pathSeparator {} {
    return [expr {$::tcl_platform(platform) eq "windows" ? ";" : ":"}]
}

proc ::svvs::toolchain::toolRoots {} {
    set roots {}
    if {[info exists ::env(RTL_EXPLORER_TOOLS)] && $::env(RTL_EXPLORER_TOOLS) ne ""} {
        lappend roots $::env(RTL_EXPLORER_TOOLS)
    }
    set root [::svvs::toolchain::appRoot]
    lappend roots [file join $root tools] [file join $root .tools]

    # Compatibility with the development workstation. Installed packages use
    # the application-local tools directory above.
    if {$::tcl_platform(platform) eq "windows" && [file isdirectory D:/RTL_EXP_tools]} {
        lappend roots D:/RTL_EXP_tools
    }
    set result {}
    foreach path $roots {
        if {$path eq ""} { continue }
        set normalized [file normalize $path]
        if {$normalized ni $result} { lappend result $normalized }
    }
    return $result
}

proc ::svvs::toolchain::firstFile {paths} {
    foreach path $paths {
        if {$path ne "" && [file exists $path] && ![file isdirectory $path]} {
            return [file normalize $path]
        }
    }
    return ""
}

proc ::svvs::toolchain::ossRoots {} {
    set result {}
    foreach tools [::svvs::toolchain::toolRoots] {
        foreach candidate [list \
                [file join $tools oss-cad-suite] \
                [file join $tools oss-cad-suite oss-cad-suite]] {
            if {[file isdirectory [file join $candidate bin]] && $candidate ni $result} {
                lappend result [file normalize $candidate]
            }
        }
    }
    return $result
}

proc ::svvs::toolchain::ossRootFor {path} {
    if {$path eq ""} { return "" }
    set normalized [file normalize $path]
    foreach root [::svvs::toolchain::ossRoots] {
        set prefix "[file normalize $root][file separator]"
        if {[string first $prefix $normalized] == 0} { return $root }
    }
    return ""
}

proc ::svvs::toolchain::pathExecutable {names} {
    foreach name $names {
        set resolved [auto_execok $name]
        if {$resolved ne ""} { return [file normalize [lindex $resolved 0]] }
    }
    return ""
}

proc ::svvs::toolchain::ossExecutable {name} {
    set suffix [expr {$::tcl_platform(platform) eq "windows" ? ".exe" : ""}]
    set candidates {}
    foreach root [::svvs::toolchain::ossRoots] {
        lappend candidates [file join $root bin ${name}${suffix}]
    }
    set found [::svvs::toolchain::firstFile $candidates]
    if {$found ne ""} { return $found }
    return [::svvs::toolchain::pathExecutable [list ${name}${suffix} $name]]
}

proc ::svvs::toolchain::yosys {} {
    set found [::svvs::toolchain::ossExecutable yosys]
    if {$found ne ""} { return $found }
    set candidates {}
    foreach root [::svvs::toolchain::toolRoots] {
        lappend candidates [file join $root yowasp-env bin yowasp-yosys.exe]
    }
    return [::svvs::toolchain::firstFile $candidates]
}

proc ::svvs::toolchain::sv2v {} {
    set candidates {}
    set suffix [expr {$::tcl_platform(platform) eq "windows" ? ".exe" : ""}]
    foreach root [::svvs::toolchain::toolRoots] {
        foreach relative [list \
                [file join sv2v sv2v${suffix}] \
                [file join sv2v sv2v-Windows sv2v.exe] \
                [file join sv2v sv2v-Linux sv2v]] {
            lappend candidates [file join $root $relative]
        }
    }
    set found [::svvs::toolchain::firstFile $candidates]
    if {$found ne ""} { return $found }
    return [::svvs::toolchain::pathExecutable [list sv2v${suffix} sv2v]]
}

proc ::svvs::toolchain::python {} {
    set candidates {}
    foreach root [::svvs::toolchain::ossRoots] {
        lappend candidates \
            [file join $root lib python3.exe] \
            [file join $root lib python3] \
            [file join $root bin python3] \
            [file join $root bin tabbypy3]
    }
    foreach root [::svvs::toolchain::toolRoots] {
        lappend candidates [file join $root yowasp-env bin python.exe]
    }
    set found [::svvs::toolchain::firstFile $candidates]
    if {$found ne ""} { return $found }
    return [::svvs::toolchain::pathExecutable {python3.exe python.exe python3 python}]
}

proc ::svvs::toolchain::compiler {} {
    set candidates {}
    set app [::svvs::toolchain::appRoot]
    lappend candidates \
        [file join $app runtime bin x86_64-conda-linux-gnu-c++] \
        [file join $app runtime bin aarch64-conda-linux-gnu-c++]
    foreach root [::svvs::toolchain::toolRoots] {
        lappend candidates \
            [file join $root w64devkit bin g++.exe] \
            [file join $root w64devkit w64devkit bin g++.exe]
    }
    set found [::svvs::toolchain::firstFile $candidates]
    if {$found ne ""} { return $found }
    return [::svvs::toolchain::pathExecutable \
        {g++.exe clang++.exe g++ clang++ x86_64-conda-linux-gnu-c++ aarch64-conda-linux-gnu-c++}]
}

proc ::svvs::toolchain::cxxrtlInclude {} {
    set candidates {}
    foreach root [::svvs::toolchain::ossRoots] {
        lappend candidates [file join $root share yosys include backends cxxrtl runtime]
    }
    foreach tools [::svvs::toolchain::toolRoots] {
        foreach base [glob -nocomplain [file join $tools yowasp-env lib \
                python* site-packages yowasp_yosys share include]] {
            lappend candidates [file join $base backends cxxrtl runtime]
        }
    }
    foreach path $candidates {
        if {[file exists [file join $path cxxrtl cxxrtl.h]]} {
            return [file normalize $path]
        }
    }
    foreach base {/usr/share/yosys/include /usr/local/share/yosys/include} {
        set path [file join $base backends cxxrtl runtime]
        if {[file exists [file join $path cxxrtl cxxrtl.h]]} { return $path }
    }
    return ""
}

proc ::svvs::toolchain::buildDirectory {} {
    if {$::tcl_platform(platform) eq "windows" && [info exists ::env(LOCALAPPDATA)]} {
        set base [file join $::env(LOCALAPPDATA) RTLExplorer]
    } elseif {[info exists ::env(XDG_CACHE_HOME)] && $::env(XDG_CACHE_HOME) ne ""} {
        set base [file join $::env(XDG_CACHE_HOME) rtl-explorer]
    } elseif {[info exists ::env(HOME)] && $::env(HOME) ne ""} {
        set base [file join $::env(HOME) .cache rtl-explorer]
    } else {
        set base [file join [pwd] .rtl_explorer]
    }
    set path [file join $base build]
    file mkdir $path
    return [file normalize $path]
}

proc ::svvs::toolchain::prependPath {directory} {
    if {$directory eq "" || ![file isdirectory $directory]} { return }
    set separator [::svvs::toolchain::pathSeparator]
    set current [expr {[info exists ::env(PATH)] ? $::env(PATH) : ""}]
    set entries [split $current $separator]
    if {$directory ni $entries} {
        set ::env(PATH) "$directory$separator$current"
    }
}

proc ::svvs::toolchain::prependEnvironmentPath {name directory} {
    if {$directory eq "" || ![file isdirectory $directory]} { return }
    set separator [::svvs::toolchain::pathSeparator]
    set current [expr {[info exists ::env($name)] ? $::env($name) : ""}]
    set entries [split $current $separator]
    if {$directory ni $entries} {
        set ::env($name) [expr {$current eq "" ? $directory : "$directory$separator$current"}]
    }
}

proc ::svvs::toolchain::activate {} {
    variable activated
    if {$activated} { return }
    set activated 1
    set privateRuntime [file join [::svvs::toolchain::appRoot] runtime]
    ::svvs::toolchain::prependPath [file join $privateRuntime bin]
    if {$::tcl_platform(platform) ne "windows" && [file isdirectory $privateRuntime]} {
        set ::env(CONDA_PREFIX) $privateRuntime
        ::svvs::toolchain::prependEnvironmentPath LD_LIBRARY_PATH [file join $privateRuntime lib]
    }
    set roots [::svvs::toolchain::ossRoots]
    if {[llength $roots] > 0} {
        set root [lindex $roots 0]
        set ::env(YOSYSHQ_ROOT) $root
        set ::env(PYTHONDONTWRITEBYTECODE) 1
        set ::env(PYTHON_EXECUTABLE) [file join $root lib \
            [expr {$::tcl_platform(platform) eq "windows" ? "python3.exe" : "python3"}]]
        if {[file exists [file join $root etc cacert.pem]]} {
            set ::env(SSL_CERT_FILE) [file join $root etc cacert.pem]
        }
        ::svvs::toolchain::prependPath [file join $root lib]
        ::svvs::toolchain::prependPath [file join $root bin]
    }
    set compiler [::svvs::toolchain::compiler]
    if {$compiler ne ""} { ::svvs::toolchain::prependPath [file dirname $compiler] }
}

proc ::svvs::toolchain::summary {} {
    return [dict create \
        yosys [::svvs::toolchain::yosys] \
        sv2v [::svvs::toolchain::sv2v] \
        python [::svvs::toolchain::python] \
        iverilog [::svvs::toolchain::ossExecutable iverilog] \
        vvp [::svvs::toolchain::ossExecutable vvp] \
        compiler [::svvs::toolchain::compiler] \
        cxxrtl [::svvs::toolchain::cxxrtlInclude]]
}
