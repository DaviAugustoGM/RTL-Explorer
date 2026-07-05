namespace eval ::svvs::sv_parser {}

proc ::svvs::sv_parser::parseFiles {paths} {
    ::svvs::console::log "Parser SystemVerilog ainda e placeholder. Arquivos recebidos: [llength $paths]"
    return [dict create files $paths modules {} connections {} diagrams {}]
}

proc ::svvs::sv_parser::parseModulesFromFiles {paths} {
    set modules {}
    foreach path $paths {
        if {![file exists $path]} {
            continue
        }

        set fh [open $path r]
        set text [read $fh]
        close $fh

        foreach moduleName [::svvs::sv_parser::moduleNamesFromText $text] {
            lappend modules [dict create \
                name $moduleName \
                instance "u_$moduleName" \
                sourcePath [file normalize $path] \
                ports [::svvs::sv_parser::portsFromModuleText $text $moduleName]]
        }
    }
    return $modules
}

proc ::svvs::sv_parser::parseFsmsFromFiles {paths} {
    set fsms {}
    set sources {}
    set queue $paths
    set visited {}
    set enumByType {}

    while {[llength $queue] > 0} {
        set path [file normalize [lindex $queue 0]]
        set queue [lrange $queue 1 end]
        if {[dict exists $visited $path] || ![file exists $path]} {
            continue
        }
        dict set visited $path 1
        if {![file exists $path]} {
            continue
        }
        set fh [open $path r]
        set text [read $fh]
        close $fh
        set text [::svvs::sv_parser::stripComments $text]
        lappend sources [dict create path $path text $text]

        foreach definition [::svvs::sv_parser::enumDefinitionsFromText $text] {
            dict set enumByType [dict get $definition type] $definition
        }
        foreach {includeFull includeName} [regexp -all -inline -- \
            {`include\s+"([^"]+)"} $text] {
            set includePath [file join [file dirname $path] $includeName]
            if {[file exists $includePath]} {
                lappend queue $includePath
            }
        }
    }

    set knownEnums [dict values $enumByType]
    foreach source $sources {
        set path [dict get $source path]
        set text [dict get $source text]
        foreach moduleName [::svvs::sv_parser::moduleNamesFromText $text] {
            set moduleText [::svvs::sv_parser::moduleText $text $moduleName]
            foreach fsm [::svvs::sv_parser::fsmsFromModuleText \
                    $moduleText $moduleName $path $knownEnums] {
                lappend fsms $fsm
            }
        }
    }
    return $fsms
}

proc ::svvs::sv_parser::enumDefinitionsFromText {text} {
    set definitions {}
    set enumPattern {(?is)\mtypedef\s+enum(?:\s+[A-Za-z_][A-Za-z0-9_$]*)?(?:\s*\[[^]]+\])?\s*\{([^\}]+)\}\s*([A-Za-z_][A-Za-z0-9_$]*)\s*;}
    foreach {full enumBody typeName} [regexp -all -inline -- $enumPattern $text] {
        set states {}
        set values {}
        set nextValue 0
        foreach rawState [split $enumBody ,] {
            set rawState [string trim $rawState]
            if {[regexp {^([A-Za-z_][A-Za-z0-9_$]*)(?:\s*=\s*(.+))?$} $rawState -> stateName literal] &&
                [lsearch -exact $states $stateName] < 0} {
                if {$literal ne ""} {
                    set parsed [::svvs::sv_parser::literalToInt $literal]
                    if {$parsed ne ""} { set nextValue $parsed }
                }
                lappend states $stateName
                dict set values $stateName $nextValue
                incr nextValue
            }
        }
        if {[llength $states] >= 2} {
            lappend definitions [dict create type $typeName states $states values $values]
        }
    }
    return $definitions
}

proc ::svvs::sv_parser::literalToInt {literal} {
    set literal [string map {_ ""} [string trim $literal]]
    if {[regexp -nocase {^(?:[0-9]+)?'([bhd])([0-9a-f]+)$} $literal -> base digits]} {
        switch -nocase -- $base {
            b {
                set value 0
                foreach digit [split $digits ""] {
                    if {$digit ni {0 1}} { return "" }
                    set value [expr {($value << 1) | $digit}]
                }
                return $value
            }
            h { scan $digits %x value; return $value }
            d { return [expr {int($digits)}] }
        }
    }
    if {[string is integer -strict $literal]} { return $literal }
    return ""
}

proc ::svvs::sv_parser::stripComments {text} {
    set text [regsub -all {(?s)/\*.*?\*/} $text ""]
    return [regsub -all {//[^\n]*} $text ""]
}

proc ::svvs::sv_parser::moduleText {text moduleName} {
    set pattern [format {(?is)\mmodule\s+%s\M.*?\mendmodule\M} $moduleName]
    if {[regexp -- $pattern $text match]} {
        return $match
    }
    return $text
}

proc ::svvs::sv_parser::fsmsFromModuleText {text moduleName path {knownEnums {}}} {
    set fsms {}
    set definitionsByType {}
    foreach definition $knownEnums {
        dict set definitionsByType [dict get $definition type] $definition
    }
    foreach definition [::svvs::sv_parser::enumDefinitionsFromText $text] {
        dict set definitionsByType [dict get $definition type] $definition
    }

    foreach typeName [dict keys $definitionsByType] {
        set states [dict get [dict get $definitionsByType $typeName] states]
        set stateValues [dict get [dict get $definitionsByType $typeName] values]
        if {[llength $states] < 2} {
            continue
        }

        set variables {}
        set declarationPattern [format {\m%s\M\s+([^;]+);} $typeName]
        foreach {declaration names} [regexp -all -inline -nocase -- $declarationPattern $text] {
            foreach rawName [split $names ,] {
                if {[regexp {^\s*([A-Za-z_][A-Za-z0-9_$]*)} $rawName -> variable]} {
                    lappend variables $variable
                }
            }
        }
        set variables [lsort -unique $variables]

        foreach caseVar $variables {
            set casePattern [format {(?is)\mcase(?:z|x)?\s*\(\s*%s\s*\)(.*?)\mendcase\M} $caseVar]
            foreach {caseFull caseBody} [regexp -all -inline -- $casePattern $text] {
                set transitions [::svvs::sv_parser::transitionsFromCase \
                    $caseBody $caseVar $variables $states]
                if {[llength $transitions] == 0} {
                    continue
                }
                set fsm [dict create \
                    name "${moduleName}_${caseVar}" \
                    module $moduleName \
                    file $path \
                    stateVariable $caseVar \
                    stateType $typeName \
                    states $states \
                    stateValues $stateValues \
                    transitions $transitions]
                set resetInfo [::svvs::sv_parser::resetInfoFromAlwaysFf \
                    $text $caseVar $states]
                if {$resetInfo ne ""} {
                    dict set fsm initialState [dict get $resetInfo state]
                    dict set fsm resetCondition [dict get $resetInfo condition]
                }
                lappend fsms $fsm
            }
        }
    }
    return $fsms
}

proc ::svvs::sv_parser::resetInfoFromAlwaysFf {text stateVariable states} {
    set assignmentPattern [format {\m%s\M\s*<=\s*([A-Za-z_][A-Za-z0-9_$]*)} $stateVariable]
    set offset 0
    while {[regexp -indices -start $offset -- $assignmentPattern $text fullRange stateRange]} {
        set target [string range $text [lindex $stateRange 0] [lindex $stateRange 1]]
        set offset [expr {[lindex $fullRange 1] + 1}]
        if {[lsearch -exact $states $target] < 0} {
            continue
        }

        set prefixStart [expr {max(0, [lindex $fullRange 0] - 400)}]
        set prefix [string range $text $prefixStart [expr {[lindex $fullRange 0] - 1}]]
        set resetCondition ""
        foreach {ifFull condition} [regexp -all -inline -nocase -- \
                {\mif\s*\(([^)]*)\)} $prefix] {
            if {[regexp -nocase {(rst|reset)} $condition]} {
                set resetCondition [string trim [regsub -all {\s+} $condition " "]]
            }
        }
        if {$resetCondition ne ""} {
            return [dict create state $target condition $resetCondition]
        }
    }
    return ""
}

proc ::svvs::sv_parser::negateCondition {condition} {
    set condition [string trim $condition]
    if {[regexp {^!\s*([A-Za-z_][A-Za-z0-9_$]*)$} $condition -> identifier]} {
        return $identifier
    }
    if {[regexp {^!\s*\((.*)\)$} $condition -> inner]} {
        return [string trim $inner]
    }
    if {[regexp {^[A-Za-z_][A-Za-z0-9_$]*$} $condition]} {
        return "!$condition"
    }
    return "!($condition)"
}

proc ::svvs::sv_parser::combineConditions {outer inner} {
    set outer [string trim $outer]
    set inner [string trim $inner]
    if {$outer eq "" || $outer eq "default"} {
        return $inner
    }
    if {$inner eq "" || $inner eq "default" || $outer eq $inner} {
        return $outer
    }
    return "$outer && $inner"
}

proc ::svvs::sv_parser::transitionsFromCase {caseBody caseVar variables states} {
    set labels [regexp -all -inline -indices -lineanchor -- \
        {^\s*([A-Za-z_][A-Za-z0-9_$]*)\s*:} $caseBody]
    set entries {}
    foreach {fullRange nameRange} $labels {
        set source [string range $caseBody [lindex $nameRange 0] [lindex $nameRange 1]]
        lappend entries [list $source $fullRange]
    }

    set transitions {}
    set seen {}
    for {set i 0} {$i < [llength $entries]} {incr i} {
        lassign [lindex $entries $i] source fullRange
        set start [expr {[lindex $fullRange 1] + 1}]
        if {$i + 1 < [llength $entries]} {
            set end [expr {[lindex [lindex [lindex $entries [expr {$i + 1}]] 1] 0] - 1}]
        } else {
            set end [expr {[string length $caseBody] - 1}]
        }
        set branch [string range $caseBody $start $end]
        if {[lsearch -exact $states $source] < 0} {
            continue
        }

        set assignmentVars {}
        foreach variable $variables {
            if {$variable ne $caseVar} {
                lappend assignmentVars $variable
            }
        }
        lappend assignmentVars $caseVar
        set alternatives [join $assignmentVars |]
        if {$alternatives eq ""} {
            continue
        }
        set assignmentPattern [format {\m(%s)\M\s*(<=|=)\s*([^;]+)} $alternatives]
        set offset 0
        set previousEnd 0
        set lastCondition ""
        while {[regexp -indices -start $offset -- $assignmentPattern $branch \
                fullRange varRange operatorRange rhsRange]} {
            set rhs [string trim [string range $branch [lindex $rhsRange 0] [lindex $rhsRange 1]]]
            set prefix [string range $branch $previousEnd [expr {[lindex $fullRange 0] - 1}]]
            set baseCondition "default"
            foreach {ifFull ifCondition} [regexp -all -inline -nocase -- \
                {\mif\s*\(([^)]*)\)} $prefix] {
                set baseCondition [string trim [regsub -all {\s+} $ifCondition " "]]
            }
            if {$baseCondition eq "default" && [regexp -nocase {\melse\M} $prefix]} {
                if {$lastCondition ne ""} {
                    set baseCondition [::svvs::sv_parser::negateCondition $lastCondition]
                }
            } elseif {$baseCondition ne "default"} {
                set lastCondition $baseCondition
            }

            set targets {}
            if {[regexp {^\s*(.*?)\s*\?\s*([A-Za-z_][A-Za-z0-9_$]*)\s*:\s*([A-Za-z_][A-Za-z0-9_$]*)} \
                    $rhs -> ternaryCondition trueTarget falseTarget]} {
                set ternaryCondition [string trim $ternaryCondition]
                if {[lsearch -exact $states $trueTarget] >= 0} {
                    lappend targets [list $trueTarget \
                        [::svvs::sv_parser::combineConditions $baseCondition $ternaryCondition]]
                }
                if {[lsearch -exact $states $falseTarget] >= 0} {
                    set falseCondition [::svvs::sv_parser::negateCondition $ternaryCondition]
                    lappend targets [list $falseTarget \
                        [::svvs::sv_parser::combineConditions $baseCondition $falseCondition]]
                }
            } else {
                foreach identifier [regexp -all -inline {[A-Za-z_][A-Za-z0-9_$]*} $rhs] {
                    if {[lsearch -exact $states $identifier] >= 0} {
                        lappend targets [list $identifier $baseCondition]
                        break
                    }
                }
            }

            foreach targetInfo $targets {
                lassign $targetInfo target condition
                set key "$source|$target|$condition"
                if {![dict exists $seen $key]} {
                    dict set seen $key 1
                    lappend transitions [dict create from $source to $target condition $condition]
                }
            }
            set previousEnd [expr {[lindex $fullRange 1] + 1}]
            set offset $previousEnd
        }
    }
    return $transitions
}

proc ::svvs::sv_parser::moduleNamesFromText {text} {
    set names {}
    set clean [regsub -all {//[^\n]*} $text ""]
    foreach {- name} [regexp -all -inline {\mmodule\s+([A-Za-z_][A-Za-z0-9_$]*)} $clean] {
        if {[lsearch -exact $names $name] < 0} {
            lappend names $name
        }
    }
    return $names
}

proc ::svvs::sv_parser::portsFromModuleText {text moduleName} {
    set ports {}
    set pattern "\\mmodule\\s+$moduleName\\M\\s*(?:#\\s*\\(.*?\\)\\s*)?\\((.*?)\\)\\s*;"
    if {![regexp -nocase -lineanchor -- $pattern $text -> header]} {
        return $ports
    }

    # Remove comments before splitting. A comment after a comma otherwise lands
    # in the same chunk as the next ANSI port declaration and hides that port.
    set header [::svvs::sv_parser::stripComments $header]
    foreach raw [split $header ","] {
        set item [string trim $raw]
        if {$item eq ""} {
            continue
        }
        if {[regexp {(input|output|inout)\s+(?:wire|logic|reg)?\s*(\[[^]]+\])?\s*([A-Za-z_][A-Za-z0-9_$]*)} $item -> dir range name]} {
            set width [::svvs::sv_parser::widthFromRange $range]
            if {$dir eq "inout"} {
                set dir input
            }
            lappend ports [dict create name $name direction $dir width $width]
        }
    }
    return $ports
}

proc ::svvs::sv_parser::widthFromRange {range} {
    if {$range eq ""} {
        return 1
    }
    if {[regexp {\[\s*([0-9]+)\s*:\s*([0-9]+)\s*\]} $range -> left right]} {
        return [expr {abs($left - $right) + 1}]
    }
    return 1
}
