namespace eval ::svvs::simulation_model {
    variable buildDir ""
    variable topModule rtl_explorer_top
}

proc ::svvs::simulation_model::safeName {value} {
    set name [regsub -all {[^A-Za-z0-9_$]} $value _]
    if {$name eq "" || [regexp {^[0-9]} $name]} {
        set name "n_$name"
    }
    return $name
}

proc ::svvs::simulation_model::portRecord {tag} {
    if {![regexp {^port:([^:]+):(.+)$} $tag -> blockId portName]} {
        return ""
    }
    if {![info exists ::svvs::canvas_blocks::blocks($blockId)]} {
        return ""
    }
    set module [dict get $::svvs::canvas_blocks::blocks($blockId) module]
    foreach port [dict get $module ports] {
        if {[dict get $port name] eq $portName} {
            return [dict create tag $tag block $blockId module $module port $port]
        }
    }
    return ""
}

proc ::svvs::simulation_model::diagramModel {} {
    set allPorts {}
    set adjacency {}
    foreach id [lsort [array names ::svvs::canvas_blocks::blocks]] {
        set module [dict get $::svvs::canvas_blocks::blocks($id) module]
        foreach port [dict get $module ports] {
            set tag "port:$id:[dict get $port name]"
            dict set allPorts $tag [dict create tag $tag block $id module $module port $port]
            dict set adjacency $tag {}
        }
    }

    foreach connection [::svvs::canvas_connections::exportConnectionData] {
        set from [dict get $connection from]
        set to [dict get $connection to]
        if {![dict exists $allPorts $from] || ![dict exists $allPorts $to]} {
            continue
        }
        dict lappend adjacency $from $to
        dict lappend adjacency $to $from
    }

    set components {}
    set visited {}
    foreach start [dict keys $allPorts] {
        if {[dict exists $visited $start]} {
            continue
        }
        set queue [list $start]
        set members {}
        while {[llength $queue] > 0} {
            set current [lindex $queue 0]
            set queue [lrange $queue 1 end]
            if {[dict exists $visited $current]} {
                continue
            }
            dict set visited $current 1
            lappend members [dict get $allPorts $current]
            foreach neighbor [dict get $adjacency $current] {
                if {![dict exists $visited $neighbor]} {
                    lappend queue $neighbor
                }
            }
        }
        lappend components $members
    }

    set inputs {}
    set outputs {}
    set nets {}
    set portNets {}
    set errors {}
    set traces {}
    set signalBlocks {}
    set clocks {}
    set netIndex 0
    foreach members $components {
        incr netIndex
        set widths {}
        set drivers {}
        set virtualSources {}
        set probes {}
        set sinks {}
        foreach record $members {
            set port [dict get $record port]
            set module [dict get $record module]
            set kind [::svvs::simulation_components::kind $module]
            lappend widths [dict get $port width]
            if {$kind in {input clock} && [dict get $port direction] eq "output"} {
                lappend virtualSources $record
            } elseif {[dict get $port direction] eq "output"} {
                lappend drivers $record
            } else {
                lappend sinks $record
                if {$kind eq "probe"} { lappend probes $record }
            }
        }
        set widths [lsort -unique -integer $widths]
        if {[llength $widths] != 1} {
            lappend errors "Uma conexao possui portas com larguras diferentes: [join $widths {, }]."
        }
        set width [lindex $widths 0]
        if {$width eq ""} { set width 1 }
        if {[llength $drivers] + [llength $virtualSources] > 1} {
            set labels {}
            foreach driver [concat $drivers $virtualSources] {
                set module [dict get $driver module]
                set port [dict get $driver port]
                lappend labels "[dict get $module instance].[dict get $port name]"
            }
            lappend errors "Mais de uma saida dirige a mesma rede: [join $labels {, }]."
        }

        set netName "net_$netIndex"
        foreach record $members {
            dict set portNets [dict get $record tag] $netName
        }
        lappend nets [dict create name $netName width $width members $members]

        set inputName ""
        if {[llength $drivers] == 0} {
            if {[llength $virtualSources] > 0} {
                set first [lindex $virtualSources 0]
            } elseif {[llength $sinks] > 0} {
                set first [lindex $sinks 0]
            } else {
                continue
            }
            set module [dict get $first module]
            set port [dict get $first port]
            set external [::svvs::simulation_model::safeName \
                "[dict get $module instance]__[dict get $port name]"]
            set inputName $external
            set inputData [dict create name $external width $width net $netName members $members]
            if {[llength $virtualSources] > 0} {
                set source [lindex $virtualSources 0]
                set sourceModule [dict get $source module]
                set sourceKind [::svvs::simulation_components::kind $sourceModule]
                set sourceBlock [dict get $source block]
                dict set inputData sourceBlock $sourceBlock
                dict set inputData sourceKind $sourceKind
                dict set inputData initialValue [::svvs::simulation_components::config $sourceModule value 0]
                lappend signalBlocks [dict create block $sourceBlock kind $sourceKind signal $external \
                    width $width base [::svvs::simulation_components::config $sourceModule base bin]]
                if {[::svvs::simulation_components::config $sourceModule trace 1]} {
                    lappend traces [dict create name $external label [::svvs::simulation_components::displayName $sourceModule] \
                        width $width base [::svvs::simulation_components::config $sourceModule base bin] block $sourceBlock]
                }
                if {$sourceKind eq "clock"} {
                    set frequency [::svvs::simulation_components::config $sourceModule frequency 1.0]
                    dict set inputData frequency $frequency
                    lappend clocks [dict create name $external frequency $frequency block $sourceBlock]
                }
            }
            lappend inputs $inputData
        }
        set outputName ""
        foreach driver $drivers {
            set module [dict get $driver module]
            set port [dict get $driver port]
            set external [::svvs::simulation_model::safeName \
                "[dict get $module instance]__[dict get $port name]"]
            lappend outputs [dict create name $external width $width net $netName source $driver]
            if {$outputName eq ""} { set outputName $external }
        }
        foreach probe $probes {
            set probeModule [dict get $probe module]
            set probeBlock [dict get $probe block]
            set observed [expr {$outputName ne "" ? $outputName : $inputName}]
            if {$observed eq ""} { continue }
            set base [::svvs::simulation_components::config $probeModule base hex]
            set valueMap [::svvs::simulation_components::config $probeModule valueMap {}]
            lappend signalBlocks [dict create block $probeBlock kind probe signal $observed width $width base $base]
            if {[::svvs::simulation_components::config $probeModule trace 1]} {
                lappend traces [dict create name $observed label [::svvs::simulation_components::displayName $probeModule] \
                    width $width base $base valueMap $valueMap block $probeBlock]
            }
        }
    }

    return [dict create \
        inputs $inputs outputs $outputs nets $nets portNets $portNets errors $errors \
        traces $traces signalBlocks $signalBlocks clocks $clocks]
}

proc ::svvs::simulation_model::widthDecl {width} {
    if {$width <= 1} {
        return ""
    }
    return [format {[%d:0] } [expr {$width - 1}]]
}

proc ::svvs::simulation_model::writeTop {path model} {
    variable topModule
    set declarations {}
    set portNames {}
    foreach signal [dict get $model inputs] {
        set name [dict get $signal name]
        lappend portNames $name
        lappend declarations "    input logic [::svvs::simulation_model::widthDecl [dict get $signal width]]$name"
    }
    foreach signal [dict get $model outputs] {
        set name [dict get $signal name]
        lappend portNames $name
        lappend declarations "    output logic [::svvs::simulation_model::widthDecl [dict get $signal width]]$name"
    }

    set lines [list "module ${topModule}(" "[join $declarations ",\n"]" ");" ""]
    foreach net [dict get $model nets] {
        lappend lines "    logic [::svvs::simulation_model::widthDecl [dict get $net width]][dict get $net name];"
    }
    lappend lines ""
    foreach signal [dict get $model inputs] {
        lappend lines "    assign [dict get $signal net] = [dict get $signal name];"
    }
    foreach signal [dict get $model outputs] {
        lappend lines "    assign [dict get $signal name] = [dict get $signal net];"
    }
    lappend lines ""

    set portNets [dict get $model portNets]
    foreach id [lsort [array names ::svvs::canvas_blocks::blocks]] {
        set module [dict get $::svvs::canvas_blocks::blocks($id) module]
        if {[::svvs::simulation_components::isVirtual $module]} { continue }
        set moduleName [::svvs::simulation_model::safeName [dict get $module name]]
        set instance [::svvs::simulation_model::safeName [dict get $module instance]]
        set connections {}
        foreach port [dict get $module ports] {
            set tag "port:$id:[dict get $port name]"
            if {[dict exists $portNets $tag]} {
                lappend connections "        .[dict get $port name]([dict get $portNets $tag])"
            }
        }
        lappend lines "    $moduleName $instance ("
        lappend lines [join $connections ",\n"]
        lappend lines "    );" ""
    }
    lappend lines "endmodule"

    set handle [open $path w]
    puts $handle [join $lines "\n"]
    close $handle
}

proc ::svvs::simulation_model::yosysExecutable {} {
    foreach candidate {yosys.exe yosys} {
        set resolved [auto_execok $candidate]
        if {$resolved ne ""} {
            return $resolved
        }
    }
    set bundled [file join [file dirname $::APP_DIR] .tools yowasp-env bin yowasp-yosys.exe]
    if {[file exists $bundled]} {
        return $bundled
    }
    return ""
}

proc ::svvs::simulation_model::pythonExecutable {} {
    foreach candidate [list \
            [file join [file dirname $::APP_DIR] .tools yowasp-env bin python.exe] \
            [auto_execok python.exe] \
            [auto_execok python] \
            {C:/Program Files/Inkscape/bin/python.exe}] {
        if {$candidate ne "" && [file exists $candidate]} {
            return $candidate
        }
    }
    return ""
}

proc ::svvs::simulation_model::yosysQuote {path} {
    return "\"[string map {\\ / \" \\\"} [file normalize $path]]\""
}

proc ::svvs::simulation_model::filesForDiagram {} {
    set moduleNames {}
    foreach id [array names ::svvs::canvas_blocks::blocks] {
        set module [dict get $::svvs::canvas_blocks::blocks($id) module]
        if {[::svvs::simulation_components::isVirtual $module]} { continue }
        dict set moduleNames [dict get $module name] 1
    }
    if {[dict size $moduleNames] == 0} { return {} }

    set modulePaths {}
    set moduleTexts {}
    foreach path $::svvs::project_tree::projectFiles {
        if {![file exists $path]} { continue }
        set handle [open $path r]
        set text [read $handle]
        close $handle
        foreach name [::svvs::sv_parser::moduleNamesFromText $text] {
            dict set modulePaths $name $path
            dict set moduleTexts $name $text
        }
    }
    set selected {}
    set visited {}
    set queue [dict keys $moduleNames]
    while {[llength $queue] > 0} {
        set name [lindex $queue 0]
        set queue [lrange $queue 1 end]
        if {[dict exists $visited $name]} { continue }
        dict set visited $name 1
        if {![dict exists $modulePaths $name]} { continue }
        lappend selected [dict get $modulePaths $name]
        set text [dict get $moduleTexts $name]
        foreach dependency [dict keys $modulePaths] {
            if {$dependency eq $name || [dict exists $visited $dependency]} { continue }
            set escaped [regsub -all {([][(){}.*+?^$\\|])} $dependency {\\\1}]
            set pattern [format {(?is)\m%s\M\s+(?:#\s*\(.*?\)\s*)?\m[A-Za-z_][A-Za-z0-9_$]*\M\s*\(} $escaped]
            if {[regexp -- $pattern $text]} { lappend queue $dependency }
        }
    }
    if {[llength $selected] == 0} {
        return $::svvs::project_tree::projectFiles
    }
    return [lsort -unique $selected]
}

proc ::svvs::simulation_model::packageInfo {} {
    set packages {}
    foreach path $::svvs::project_tree::projectFiles {
        if {![file exists $path]} { continue }
        set handle [open $path r]
        set text [read $handle]
        close $handle
        foreach {full packageName body} [regexp -all -inline -nocase -- \
                {(?is)\mpackage\s+([A-Za-z_][A-Za-z0-9_$]*)\s*;(.*?)\mendpackage\M} $text] {
            set symbols {}
            foreach {enumFull enumBody typeName} [regexp -all -inline -- \
                    {(?is)\mtypedef\s+enum\M[^\{]*\{([^\}]+)\}\s*([A-Za-z_][A-Za-z0-9_$]*)\s*;} $body] {
                lappend symbols $typeName
                foreach entry [split $enumBody ,] {
                    if {[regexp {^\s*([A-Za-z_][A-Za-z0-9_$]*)} $entry -> symbol]} {
                        lappend symbols $symbol
                    }
                }
            }
            foreach {decl symbol} [regexp -all -inline -- \
                    {(?im)\m(?:localparam|parameter)\M[^;=]*\m([A-Za-z_][A-Za-z0-9_$]*)\s*=} $body] {
                lappend symbols $symbol
            }
            dict set packages $packageName [dict create path $path \
                basename [file tail $path] symbols [lsort -unique $symbols]]
        }
    }
    return $packages
}

proc ::svvs::simulation_model::qualifyPackageImports {text packages} {
    foreach {full packageName} [regexp -all -inline -nocase -- \
            {\mimport\s+([A-Za-z_][A-Za-z0-9_$]*)::\*\s*;} $text] {
        if {![dict exists $packages $packageName]} {
            set text [string map [list $full ""] $text]
            continue
        }
        foreach symbol [dict get $packages $packageName symbols] {
            set qualified "${packageName}::$symbol"
            set marker "__RTLX_${packageName}_${symbol}__"
            set text [string map [list $qualified $marker] $text]
            set escaped [regsub -all {([][(){}.*+?^$\\|])} $symbol {\\\1}]
            regsub -all -- "\\m${escaped}\\M" $text $qualified text
            set text [string map [list $marker $qualified] $text]
        }
        set text [string map [list $full ""] $text]
    }
    return $text
}

proc ::svvs::simulation_model::prepareSourceFiles {files directory} {
    file mkdir $directory
    foreach stale [glob -nocomplain -directory $directory *] {
        if {[file isfile $stale]} { file delete -force $stale }
    }
    set packages [::svvs::simulation_model::packageInfo]
    set prepared {}
    set packageBasenames {}
    set index 0
    foreach packageName [dict keys $packages] {
        set info [dict get $packages $packageName]
        set source [dict get $info path]
        set target [file join $directory [format "%03d_%s" [incr index] [file tail $source]]]
        file copy -force $source $target
        lappend prepared $target
        lappend packageBasenames [dict get $info basename]
    }
    foreach source $files {
        set isPackage 0
        foreach packageName [dict keys $packages] {
            if {[file normalize $source] eq [file normalize [dict get $packages $packageName path]]} {
                set isPackage 1
                break
            }
        }
        if {$isPackage} { continue }
        set handle [open $source r]
        set text [read $handle]
        close $handle
        foreach basename $packageBasenames {
            set escaped [regsub -all {([][(){}.*+?^$\\|])} $basename {\\\1}]
            regsub -all -nocase -- "`include\\s+\"${escaped}\"" $text "" text
        }
        set text [::svvs::simulation_model::qualifyPackageImports $text $packages]
        set target [file join $directory [format "%03d_%s" [incr index] [file tail $source]]]
        set handle [open $target w]
        fconfigure $handle -encoding utf-8 -translation lf
        puts -nonewline $handle $text
        close $handle
        lappend prepared $target
    }
    return $prepared
}

proc ::svvs::simulation_model::prepare {} {
    variable buildDir
    variable topModule
    set model [::svvs::simulation_model::diagramModel]
    if {[llength [dict get $model errors]] > 0} {
        return [dict create ok 0 model $model message [join [dict get $model errors] "\n"]]
    }
    if {[llength [dict get $model inputs]] == 0 && [llength [dict get $model outputs]] == 0} {
        return [dict create ok 0 model $model message "Adicione pelo menos um bloco ao diagrama."]
    }

    set buildDir [file join [file dirname $::APP_DIR] .rtl_explorer_build]
    file mkdir $buildDir
    set topPath [file join $buildDir rtl_explorer_top.sv]
    set jsonPath [file join $buildDir netlist.json]
    set scriptPath [file join $buildDir synth.ys]
    ::svvs::simulation_model::writeTop $topPath $model

    set sourceFiles [::svvs::simulation_model::filesForDiagram]
    set files [::svvs::simulation_model::prepareSourceFiles \
        $sourceFiles [file join $buildDir sources]]
    set lines {}
    set includeDirs {}
    foreach path $::svvs::project_tree::projectFiles {
        lappend includeDirs [file dirname $path]
    }
    set includeDirs [lsort -unique $includeDirs]
    set includeArgs ""
    foreach dir $includeDirs {
        append includeArgs " -I[::svvs::simulation_model::yosysQuote $dir]"
    }
    foreach path $files {
        lappend lines "read_verilog -sv$includeArgs [::svvs::simulation_model::yosysQuote $path]"
    }
    lappend lines "read_verilog -sv [::svvs::simulation_model::yosysQuote $topPath]"
    lappend lines "hierarchy -check -top $topModule"
    lappend lines "proc; flatten; opt; memory; opt"
    lappend lines "write_json [::svvs::simulation_model::yosysQuote $jsonPath]"
    set handle [open $scriptPath w]
    puts $handle [join $lines "\n"]
    close $handle

    set yosys [::svvs::simulation_model::yosysExecutable]
    if {$yosys eq ""} {
        return [dict create ok 0 missingTool yosys model $model top $topPath script $scriptPath \
            message "Yosys nao foi encontrado. O projeto de sintese foi preparado, mas ainda nao pode ser executado."]
    }
    if {[catch {exec $yosys -q -s $scriptPath 2>@1} output]} {
        return [dict create ok 0 model $model message "Falha na sintese:\n$output"]
    }
    return [dict create ok 1 model $model json $jsonPath top $topPath script $scriptPath]
}
