namespace eval ::svvs::sv_parser {}

proc ::tcl::mathfunc::clog2 {value} {
    return [::svvs::sv_parser::clog2 $value]
}

proc ::svvs::sv_parser::parseFiles {paths} {
    ::svvs::console::log "Parser SystemVerilog ainda e placeholder. Arquivos recebidos: [llength $paths]"
    return [dict create files $paths modules {} connections {} diagrams {}]
}

proc ::svvs::sv_parser::parseModulesFromFiles {paths} {
    set modules {}
    set sources {}
    set combinedText ""
    foreach path $paths {
        if {![file exists $path]} {
            continue
        }

        set fh [open $path r]
        set text [read $fh]
        close $fh
        lappend sources [dict create path $path text $text]
        append combinedText "\n" $text
    }

    set interfaces [::svvs::sv_parser::interfacesFromText $combinedText]
    foreach source $sources {
        set path [dict get $source path]
        set text [dict get $source text]

        foreach moduleName [::svvs::sv_parser::moduleNamesFromText $text] {
            lappend modules [dict create \
                name $moduleName \
                instance "u_$moduleName" \
                sourcePath [file normalize $path] \
                ports [::svvs::sv_parser::portsFromModuleText $text $moduleName $interfaces]]
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

proc ::svvs::sv_parser::structuralConnectionsFromFiles {paths moduleNames} {
    set hints {}
    set instances [::svvs::sv_parser::structuralInstantiationsFromFiles $paths "" $moduleNames]
    foreach hint [::svvs::sv_parser::connectionHintsFromInstantiations $instances] {
        lappend hints $hint
    }
    return $hints
}

proc ::svvs::sv_parser::structuralInstantiationsFromFiles {paths ownerModule moduleNames} {
    set instances {}
    set sources {}
    set modulePortOrder {}
    foreach path $paths {
        if {![file exists $path]} {
            continue
        }
        set fh [open $path r]
        set text [read $fh]
        close $fh
        set clean [::svvs::sv_parser::stripComments $text]
        lappend sources [dict create path $path text $clean]
        foreach moduleName [::svvs::sv_parser::moduleNamesFromText $clean] {
            if {[lsearch -exact $moduleNames $moduleName] < 0} {
                continue
            }
            set order {}
            foreach port [::svvs::sv_parser::portsFromModuleText $clean $moduleName] {
                lappend order [dict get $port name]
            }
            dict set modulePortOrder $moduleName $order
        }
    }

    foreach source $sources {
        set clean [dict get $source text]
        foreach moduleName [::svvs::sv_parser::moduleNamesFromText $clean] {
            if {$ownerModule ne "" && ![string equal -nocase $ownerModule $moduleName]} {
                continue
            }
            set moduleText [::svvs::sv_parser::moduleText $clean $moduleName]
            foreach inst [::svvs::sv_parser::moduleInstantiationsFromText \
                    $moduleText $moduleName $moduleNames $modulePortOrder] {
                dict set inst owner $moduleName
                lappend instances $inst
            }
        }
    }
    return $instances
}

proc ::svvs::sv_parser::moduleInstantiationsFromText {text ownerModule moduleNames {modulePortOrder {}}} {
    set instances {}
    foreach type [lsort -unique $moduleNames] {
        if {[string equal -nocase $type $ownerModule]} {
            continue
        }
        set escaped [regsub -all {([][(){}.*+?^$\\|])} $type {\\\1}]
        set offset 0
        while {[regexp -indices -start $offset -nocase -- "\\m${escaped}\\M" $text match]} {
            set pos [expr {[lindex $match 1] + 1}]
            set offset $pos
            if {[::svvs::sv_parser::isModuleDeclarationAt $text [lindex $match 0]]} {
                continue
            }
            set pos [::svvs::sv_parser::skipSpaces $text $pos]
            if {[string index $text $pos] eq "#"} {
                set open [string first "(" $text $pos]
                if {$open < 0} { continue }
                set close [::svvs::sv_parser::matchingParen $text $open]
                if {$close < 0} { continue }
                set pos [::svvs::sv_parser::skipSpaces $text [expr {$close + 1}]]
            }
            if {![regexp -indices -start $pos -- {\m([A-Za-z_][A-Za-z0-9_$]*)\M} \
                    $text instanceMatch nameRange]} {
                continue
            }
            if {[lindex $instanceMatch 0] != $pos} {
                continue
            }
            set instance [string range $text {*}$nameRange]
            set pos [::svvs::sv_parser::skipSpaces $text [expr {[lindex $instanceMatch 1] + 1}]]
            if {[string index $text $pos] ne "("} {
                continue
            }
            set close [::svvs::sv_parser::matchingParen $text $pos]
            if {$close < 0} { continue }
            set after [::svvs::sv_parser::skipSpaces $text [expr {$close + 1}]]
            if {[string index $text $after] ne ";"} {
                continue
            }
            set mapText [string range $text [expr {$pos + 1}] [expr {$close - 1}]]
            set ports [::svvs::sv_parser::namedPortMapFromText $mapText]
            if {[dict size $ports] == 0 && [dict exists $modulePortOrder $type]} {
                set ports [::svvs::sv_parser::positionalPortMapFromText \
                    $mapText [dict get $modulePortOrder $type]]
            }
            lappend instances [dict create type $type instance $instance ports $ports]
            set offset [expr {$close + 1}]
        }
    }
    return $instances
}

proc ::svvs::sv_parser::connectionHintsFromInstantiations {instances} {
    set byNet {}
    set hints {}
    foreach inst $instances {
        dict for {port endpoint} [dict get $inst ports] {
            set net [dict get $endpoint net]
            if {$net eq ""} { continue }
            dict lappend byNet $net [dict create \
                module [dict get $inst type] \
                instance [dict get $inst instance] \
                port $port \
                range [dict get $endpoint range]]
        }
    }
    dict for {net endpoints} $byNet {
        if {[llength $endpoints] < 2} { continue }
        foreach a $endpoints {
            foreach b $endpoints {
                if {$a eq $b} { continue }
                lappend hints [dict create \
                    net $net \
                    fromModule [dict get $a module] \
                    fromInstance [dict get $a instance] \
                    fromPort [dict get $a port] \
                    fromRange [dict get $a range] \
                    toModule [dict get $b module] \
                    toInstance [dict get $b instance] \
                    toPort [dict get $b port] \
                    toRange [dict get $b range]]
            }
        }
    }
    return $hints
}

proc ::svvs::sv_parser::namedPortMapFromText {text} {
    set ports {}
    foreach {full port signal} [regexp -all -inline -- \
            {\.([A-Za-z_][A-Za-z0-9_$]*)\s*\(([^()]*)\)} $text] {
        set endpoint [::svvs::sv_parser::endpointFromExpression $signal]
        if {$endpoint ne ""} {
            dict set ports $port $endpoint
        }
    }
    return $ports
}

proc ::svvs::sv_parser::positionalPortMapFromText {text portOrder} {
    set ports {}
    set index 0
    foreach raw [::svvs::sv_parser::splitTopLevelCommas $text] {
        if {$index >= [llength $portOrder]} {
            break
        }
        set endpoint [::svvs::sv_parser::endpointFromExpression $raw]
        if {$endpoint ne ""} {
            dict set ports [lindex $portOrder $index] $endpoint
        }
        incr index
    }
    return $ports
}

proc ::svvs::sv_parser::splitTopLevelCommas {text} {
    set result {}
    set depth 0
    set inString 0
    set escaped 0
    set start 0
    for {set index 0} {$index < [string length $text]} {incr index} {
        set char [string index $text $index]
        if {$inString} {
            if {$escaped} { set escaped 0; continue }
            if {$char eq "\\"} { set escaped 1; continue }
            if {$char eq "\""} { set inString 0 }
            continue
        }
        if {$char eq "\""} { set inString 1; continue }
        switch -- $char {
            "(" - "[" - "{" {
                incr depth
            }
            ")" - "]" - "}" {
                if {$depth > 0} { incr depth -1 }
            }
            "," {
                if {$depth == 0} {
                    lappend result [string trim [string range $text $start [expr {$index - 1}]]]
                    set start [expr {$index + 1}]
                }
            }
        }
    }
    lappend result [string trim [string range $text $start end]]
    return $result
}

proc ::svvs::sv_parser::endpointFromExpression {expr} {
    set expr [string trim $expr]
    if {[regexp {^([A-Za-z_][A-Za-z0-9_$]*)\s*(?:\[\s*([0-9]+)(?:\s*:\s*([0-9]+))?\s*\])?$} \
            $expr -> name left right]} {
        set range ""
        if {$left ne ""} {
            set range $left
            if {$right ne ""} {
                set range "$left:$right"
            }
        }
        return [dict create net $name range $range]
    }
    return ""
}

proc ::svvs::sv_parser::skipSpaces {text position} {
    while {$position < [string length $text] &&
           [string is space [string index $text $position]]} {
        incr position
    }
    return $position
}

proc ::svvs::sv_parser::isModuleDeclarationAt {text position} {
    set before [string range $text [expr {max(0, $position - 8)}] [expr {$position - 1}]]
    return [regexp -nocase {\mmodule\s+$} $before]
}

proc ::svvs::sv_parser::matchingParen {text openIndex} {
    set depth 0
    set inString 0
    set escaped 0
    for {set index $openIndex} {$index < [string length $text]} {incr index} {
        set char [string index $text $index]
        if {$inString} {
            if {$escaped} { set escaped 0; continue }
            if {$char eq "\\"} { set escaped 1; continue }
            if {$char eq "\""} { set inString 0 }
            continue
        }
        if {$char eq "\""} { set inString 1; continue }
        if {$char eq "("} { incr depth }
        if {$char eq ")"} {
            incr depth -1
            if {$depth == 0} { return $index }
        }
    }
    return -1
}

proc ::svvs::sv_parser::moduleHeader {text moduleName} {
    set clean [::svvs::sv_parser::stripComments $text]
    set escaped [regsub -all {([][(){}.*+?^$\\|])} $moduleName {\\\1}]
    if {![regexp -indices -nocase -- "\\mmodule\\s+${escaped}\\M" $clean declaration]} { return "" }
    set position [expr {[lindex $declaration 1] + 1}]
    while {$position < [string length $clean] && [string is space [string index $clean $position]]} { incr position }
    if {[string index $clean $position] eq "#"} {
        set parameterOpen [string first "(" $clean $position]
        if {$parameterOpen < 0} { return "" }
        set parameterClose [::svvs::sv_parser::matchingParen $clean $parameterOpen]
        if {$parameterClose < 0} { return "" }
        set position [expr {$parameterClose + 1}]
    }
    set declarationEnd [string first ";" $clean $position]
    set portOpen [string first "(" $clean $position]
    if {$portOpen < 0 || ($declarationEnd >= 0 && $declarationEnd < $portOpen)} {
        return ""
    }
    set portClose [::svvs::sv_parser::matchingParen $clean $portOpen]
    if {$portClose < 0} { return "" }
    if {$declarationEnd >= 0 && $declarationEnd < $portClose} {
        return ""
    }
    return [string range $clean [expr {$portOpen + 1}] [expr {$portClose - 1}]]
}

proc ::svvs::sv_parser::portsFromModuleText {text moduleName {interfaces {}}} {
    set ports {}
    set byName {}
    set headerOrder {}
    set moduleText [::svvs::sv_parser::moduleText [::svvs::sv_parser::stripComments $text] $moduleName]
    set parameters [::svvs::sv_parser::parametersFromModuleText $moduleText]
    set header [::svvs::sv_parser::moduleHeader $text $moduleName]

    # Remove comments before splitting. A comment after a comma otherwise lands
    # in the same chunk as the next ANSI port declaration and hides that port.
    set currentDir ""
    set currentRange ""
    if {$header ne ""} {
        foreach raw [split $header ","] {
            set item [string trim $raw]
            if {$item eq ""} {
                continue
            }
            set expanded [::svvs::sv_parser::interfacePortsFromHeaderItem $item $interfaces $parameters]
            if {[llength $expanded] > 0} {
                foreach port $expanded {
                    set name [dict get $port name]
                    if {![dict exists $byName $name]} {
                        dict set byName $name $port
                        lappend headerOrder $name
                    }
                }
                set currentDir ""
                set currentRange ""
                continue
            }
            if {[regexp -nocase {^(input|output|inout)\M\s*(.*)$} $item -> dir declaration]} {
                set currentDir [string tolower $dir]
                set ranges [regexp -all -inline {\[[^]]+\]} $declaration]
                set currentRange [expr {[llength $ranges] ? [lindex $ranges 0] : ""}]
            } else {
                if {$currentDir eq ""} { continue }
                set declaration $item
                set ranges [regexp -all -inline {\[[^]]+\]} $declaration]
                if {[llength $ranges]} { set currentRange [lindex $ranges 0] }
            }
            regsub {\s*=.*$} $declaration "" declaration
            if {![regexp {([A-Za-z_][A-Za-z0-9_$]*)\s*(?:\[[^]]+\]\s*)*$} \
                    [string trim $declaration] -> name]} { continue }
            set width [::svvs::sv_parser::widthFromRange $currentRange $parameters]
            set direction [expr {$currentDir eq "inout" ? "input" : $currentDir}]
            if {![dict exists $byName $name]} {
                dict set byName $name [dict create name $name direction $direction width $width]
                lappend headerOrder $name
            }
        }
    }

    set declarationOrder {}
    foreach port [::svvs::sv_parser::declarationPortsFromModuleText $text $moduleName $parameters $interfaces] {
        dict set byName [dict get $port name] $port
        lappend declarationOrder [dict get $port name]
    }

    set order $headerOrder
    if {[llength $order] == 0} {
        set order [::svvs::sv_parser::portOrderFromHeader $header]
    }
    if {[llength $order] == 0} {
        set order $declarationOrder
    } else {
        foreach name $declarationOrder {
            if {[lsearch -exact $order $name] < 0} {
                lappend order $name
            }
        }
    }
    foreach name $order {
        if {[dict exists $byName $name]} {
            lappend ports [dict get $byName $name]
            dict unset byName $name
        }
    }
    foreach name [lsort [dict keys $byName]] {
        lappend ports [dict get $byName $name]
    }
    return $ports
}

proc ::svvs::sv_parser::interfacesFromText {text} {
    set interfaces {}
    set clean [::svvs::sv_parser::stripComments $text]
    foreach {full name body} [regexp -all -inline -nocase -- \
            {(?is)\minterface\s+([A-Za-z_][A-Za-z0-9_$]*)(?:\s*#\s*\(.*?\))?(?:\s*\(.*?\))?\s*;(.*?)\mendinterface\M} $clean] {
        set parameters [::svvs::sv_parser::parametersFromModuleText $body]
        set signals [::svvs::sv_parser::interfaceSignalsFromBody $body $parameters]
        set modports [::svvs::sv_parser::modportsFromInterfaceBody $body]
        dict set interfaces $name [dict create name $name signals $signals modports $modports]
    }
    return $interfaces
}

proc ::svvs::sv_parser::interfaceSignalsFromBody {body {parameters {}}} {
    set signals {}
    foreach {full declaration} [regexp -all -inline -nocase -- \
            {\m(?:logic|wire|reg)\M\s+([^;]+);} $body] {
        set range ""
        if {[regexp {\[[^]]+\]} $declaration range]} {
            set declaration [string map [list $range " "] $declaration]
        }
        regsub -all -nocase {\m(signed|unsigned|tri|wand|wor)\M} $declaration " " declaration
        set width [::svvs::sv_parser::widthFromRange $range $parameters]
        foreach rawName [split $declaration ,] {
            set nameText [string trim $rawName]
            regsub {\s*=.*$} $nameText "" nameText
            regsub -all {\[[^]]+\]} $nameText " " nameText
            if {[regexp {^([A-Za-z_][A-Za-z0-9_$]*)$} [string trim $nameText] -> name]} {
                dict set signals $name [dict create name $name width $width]
            }
        }
    }
    return $signals
}

proc ::svvs::sv_parser::modportsFromInterfaceBody {body} {
    set modports {}
    foreach {full name portsText} [regexp -all -inline -nocase -- \
            {(?is)\mmodport\s+([A-Za-z_][A-Za-z0-9_$]*)\s*\((.*?)\)\s*;} $body] {
        set ports {}
        set currentDir ""
        foreach raw [split $portsText ,] {
            set item [string trim $raw]
            if {$item eq ""} { continue }
            if {[regexp -nocase {^(input|output|inout)\M\s*(.*)$} $item -> dir rest]} {
                set currentDir [string tolower $dir]
                set item [string trim $rest]
            }
            if {$currentDir eq ""} { continue }
            regsub -all {\.[A-Za-z_][A-Za-z0-9_$]*$} $item "" item
            regsub -all {\[[^]]+\]} $item " " item
            if {[regexp {^([A-Za-z_][A-Za-z0-9_$]*)$} [string trim $item] -> portName]} {
                set direction [expr {$currentDir eq "inout" ? "input" : $currentDir}]
                lappend ports [dict create name $portName direction $direction]
            }
        }
        dict set modports $name $ports
    }
    return $modports
}

proc ::svvs::sv_parser::interfacePortsFromHeaderItem {item interfaces {parameters {}}} {
    set item [string trim $item]
    regsub {\s*=.*$} $item "" item
    if {![regexp {^([A-Za-z_][A-Za-z0-9_$]*)(?:\s*\.\s*([A-Za-z_][A-Za-z0-9_$]*))?\s+([A-Za-z_][A-Za-z0-9_$]*)$} \
            $item -> interfaceName modportName instanceName]} {
        return {}
    }
    set known [::svvs::sv_parser::knownInterfacePorts \
        $interfaceName $modportName $instanceName $parameters]
    if {[llength $known] > 0} {
        return $known
    }
    if {![dict exists $interfaces $interfaceName]} {
        return {}
    }
    return [::svvs::sv_parser::expandInterfacePort \
        [dict get $interfaces $interfaceName] $modportName $instanceName]
}

proc ::svvs::sv_parser::parameterOrDefault {parameters names default} {
    foreach name $names {
        if {[dict exists $parameters $name]} {
            return [dict get $parameters $name]
        }
    }
    return $default
}

proc ::svvs::sv_parser::knownInterfacePorts {interfaceName modportName instanceName {parameters {}}} {
    set normalizedInterface [string tolower $interfaceName]
    set normalizedModport [string tolower $modportName]
    if {$normalizedInterface ni {axi_lite axi4_lite axi4lite}} {
        return {}
    }
    if {$normalizedModport ni {slave master slv mst ""}} {
        return {}
    }

    set addrWidth [::svvs::sv_parser::parameterOrDefault \
        $parameters {AXI_ADDR_WIDTH ADDR_WIDTH AXI_AW AXI_ADDR_W} 32]
    set dataWidth [::svvs::sv_parser::parameterOrDefault \
        $parameters {AXI_DATA_WIDTH DATA_WIDTH AXI_DW AXI_DATA_W} 32]
    set strbWidth [expr {max(1, int($dataWidth / 8))}]

    set slavePorts {
        aw_addr  input  addr
        aw_prot  input  prot
        aw_valid input  1
        aw_ready output 1
        w_data   input  data
        w_strb   input  strb
        w_valid  input  1
        w_ready  output 1
        b_resp   output resp
        b_valid  output 1
        b_ready  input  1
        ar_addr  input  addr
        ar_prot  input  prot
        ar_valid input  1
        ar_ready output 1
        r_data   output data
        r_resp   output resp
        r_valid  output 1
        r_ready  input  1
    }

    set result {}
    foreach {signal direction widthKey} $slavePorts {
        switch -- $widthKey {
            addr { set width $addrWidth }
            data { set width $dataWidth }
            strb { set width $strbWidth }
            prot { set width 3 }
            resp { set width 2 }
            default { set width $widthKey }
        }
        if {$normalizedModport in {master mst}} {
            set direction [expr {$direction eq "input" ? "output" : "input"}]
        }
        lappend result [dict create \
            name "${instanceName}.${signal}" \
            direction $direction \
            width $width \
            interface $instanceName \
            interfaceSignal $signal]
    }
    return $result
}

proc ::svvs::sv_parser::expandInterfacePort {interface modportName instanceName} {
    set signals [dict get $interface signals]
    set result {}
    set modports [dict get $interface modports]
    if {$modportName ne "" && [dict exists $modports $modportName]} {
        foreach port [dict get $modports $modportName] {
            set signalName [dict get $port name]
            set width 1
            if {[dict exists $signals $signalName width]} {
                set width [dict get $signals $signalName width]
            }
            lappend result [dict create \
                name "${instanceName}.${signalName}" \
                direction [dict get $port direction] \
                width $width \
                interface $instanceName \
                interfaceSignal $signalName]
        }
        return $result
    }

    foreach signalName [lsort [dict keys $signals]] {
        set signal [dict get $signals $signalName]
        lappend result [dict create \
            name "${instanceName}.${signalName}" \
            direction input \
            width [dict get $signal width] \
            interface $instanceName \
            interfaceSignal $signalName]
    }
    return $result
}

proc ::svvs::sv_parser::portOrderFromHeader {header} {
    set order {}
    set currentDir ""
    foreach raw [split $header ","] {
        set item [string trim $raw]
        if {$item eq ""} { continue }
        regsub -all {\[[^]]+\]} $item " " item
        regsub -nocase {^(input|output|inout)\M} $item "" item
        regsub -nocase {\m(wire|reg|logic|signed|unsigned)\M} $item " " item
        regsub {\s*=.*$} $item "" item
        if {[regexp {([A-Za-z_][A-Za-z0-9_$]*)\s*$} [string trim $item] -> name] &&
            [lsearch -exact $order $name] < 0} {
            lappend order $name
        }
    }
    return $order
}

proc ::svvs::sv_parser::declarationPortsFromModuleText {text moduleName {parameters {}} {interfaces {}}} {
    set ports {}
    set seen {}
    set clean [::svvs::sv_parser::stripComments $text]
    set module [::svvs::sv_parser::moduleText $clean $moduleName]
    set header [::svvs::sv_parser::moduleHeader $clean $moduleName]
    if {$header ne ""} {
        set headerIndex [string first $header $module]
        if {$headerIndex >= 0} {
            set module [string range $module [expr {$headerIndex + [string length $header]}] end]
        }
    }
    foreach {full dir declaration} [regexp -all -inline -nocase -- \
            {\m(input|output|inout)\M\s+([^;]+);} $module] {
        set direction [expr {[string tolower $dir] eq "inout" ? "input" : [string tolower $dir]}]
        set range ""
        if {[regexp {\[[^]]+\]} $declaration range]} {
            set declaration [string map [list $range " "] $declaration]
        }
        regsub -all -nocase {\m(wire|reg|logic|signed|unsigned|tri|wand|wor|supply0|supply1)\M} \
            $declaration " " declaration
        set width [::svvs::sv_parser::widthFromRange $range $parameters]
        foreach rawName [split $declaration ,] {
            set nameText [string trim $rawName]
            regsub {\s*=.*$} $nameText "" nameText
            regsub -all {\[[^]]+\]} $nameText " " nameText
            if {![regexp {^([A-Za-z_][A-Za-z0-9_$]*)$} [string trim $nameText] -> name]} {
                continue
            }
            if {[dict exists $seen $name]} { continue }
            dict set seen $name 1
            lappend ports [dict create name $name direction $direction width $width]
        }
    }
    foreach {full declaration} [regexp -all -inline -nocase -- \
            {([A-Za-z_][A-Za-z0-9_$]*)(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_$]*)?\s+[A-Za-z_][A-Za-z0-9_$]*\s*;} $module] {
        set expanded [::svvs::sv_parser::interfacePortsFromHeaderItem \
            [string trimright [string trim $declaration] ";"] $interfaces $parameters]
        foreach port $expanded {
            set name [dict get $port name]
            if {[dict exists $seen $name]} { continue }
            dict set seen $name 1
            lappend ports $port
        }
    }
    return $ports
}

proc ::svvs::sv_parser::parametersFromModuleText {text} {
    set values {}
    foreach {full declaration} [regexp -all -inline -nocase -- \
            {\m(?:localparam|parameter)\M\s+([^;,\)]+)} $text] {
        regsub -all -nocase {\m(int|integer|logic|reg|wire|signed|unsigned)\M} \
            $declaration " " declaration
        regsub -all {\[[^]]+\]} $declaration " " declaration
        if {![regexp {([A-Za-z_][A-Za-z0-9_$]*)\s*=\s*(.+)$} \
                [string trim $declaration] -> name expr]} {
            continue
        }
        set expr [string trim $expr]
        set value [::svvs::sv_parser::evalIntExpression $expr $values]
        if {$value ne ""} {
            dict set values $name $value
        }
    }
    return $values
}

proc ::svvs::sv_parser::clog2 {value} {
    if {![string is integer -strict $value] || $value <= 1} {
        return 0
    }
    set result 0
    set power 1
    while {$power < $value} {
        set power [expr {$power * 2}]
        incr result
    }
    return $result
}

proc ::svvs::sv_parser::compareIdentifierLength {a b} {
    return [expr {[string length $b] - [string length $a]}]
}

proc ::svvs::sv_parser::evalIntExpression {expression {parameters {}}} {
    set expr [string trim $expression]
    regsub -all {\$clog2\s*\(} $expr {clog2(} expr
    foreach name [lsort -command ::svvs::sv_parser::compareIdentifierLength [dict keys $parameters]] {
        set escaped [regsub -all {([][(){}.*+?^$\\|])} $name {\\\1}]
        regsub -all -- "\\m${escaped}\\M" $expr [dict get $parameters $name] expr
    }
    regsub -all {_} $expr "" expr
    regsub -all -nocase {([0-9]+)?'b([01]+)} $expr {0b\2} expr
    regsub -all -nocase {([0-9]+)?'h([0-9a-f]+)} $expr {0x\2} expr
    regsub -all -nocase {([0-9]+)?'d([0-9]+)} $expr {\2} expr
    set checkExpr [regsub -all {\mclog2\M} $expr ""]
    if {[regexp {[A-Za-z_$]} $checkExpr]} {
        return ""
    }
    if {![regexp {^[0-9xXa-fA-FbBclog2+\-*/%<>=!&|~^?:(). \t]+$} $expr]} {
        return ""
    }
    if {[catch {set value [expr $expr]}]} {
        return ""
    }
    if {![string is integer -strict $value]} {
        return ""
    }
    return $value
}

proc ::svvs::sv_parser::widthFromRange {range {parameters {}}} {
    if {$range eq ""} {
        return 1
    }
    if {[regexp {\[\s*([0-9]+)\s*:\s*([0-9]+)\s*\]} $range -> left right]} {
        return [expr {abs($left - $right) + 1}]
    }
    if {[regexp {\[\s*(.+?)\s*:\s*(.+?)\s*\]} $range -> leftExpr rightExpr]} {
        set left [::svvs::sv_parser::evalIntExpression $leftExpr $parameters]
        set right [::svvs::sv_parser::evalIntExpression $rightExpr $parameters]
        if {$left ne "" && $right ne ""} {
            return [expr {abs($left - $right) + 1}]
        }
    }
    return 1
}
