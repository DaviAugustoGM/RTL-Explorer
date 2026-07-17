namespace eval ::svvs::simulation_model {
    variable buildDir ""
    variable topModule rtl_explorer_top
}

if {![info exists ::APP_DIR]} {
    set ::APP_DIR [file dirname [file normalize [info script]]]
}
if {![llength [info commands ::svvs::toolchain::yosys]]} {
    source [file join $::APP_DIR toolchain.tcl]
    ::svvs::toolchain::activate
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

    set connections [::svvs::canvas_connections::exportConnectionData]
    set slicedConnections {}
    set sliceDrivenPorts {}
    foreach connection $connections {
        set from [dict get $connection from]
        set to [dict get $connection to]
        if {![dict exists $allPorts $from] || ![dict exists $allPorts $to]} {
            continue
        }
        if {[::svvs::simulation_model::connectionHasSlice $connection]} {
            set directed [::svvs::simulation_model::directedConnection $connection $allPorts]
            if {$directed ne ""} {
                lappend slicedConnections $directed
                dict set sliceDrivenPorts [dict get $directed target] 1
            }
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
    set sliceAssignments {}
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
        set drivenBySlice 0
        foreach record $members {
            if {[dict exists $sliceDrivenPorts [dict get $record tag]]} {
                set drivenBySlice 1
                break
            }
        }
        if {[llength $drivers] == 0 && !$drivenBySlice} {
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
                "[dict get $module instance]__[dict get $first block]__[dict get $port name]"]
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
                "[dict get $module instance]__[dict get $driver block]__[dict get $port name]"]
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

    foreach connection $slicedConnections {
        set sourceTag [dict get $connection source]
        set targetTag [dict get $connection target]
        if {![dict exists $portNets $sourceTag] || ![dict exists $portNets $targetTag]} {
            continue
        }
        set sourceRecord [dict get $allPorts $sourceTag]
        set targetRecord [dict get $allPorts $targetTag]
        set sourceWidth [dict get [dict get $sourceRecord port] width]
        set targetWidth [dict get [dict get $targetRecord port] width]
        set sourceRange [dict get $connection sourceRange]
        set targetRange [dict get $connection targetRange]
        set sourceSliceWidth [::svvs::simulation_model::rangeWidthOrPort $sourceRange $sourceWidth]
        set targetSliceWidth [::svvs::simulation_model::rangeWidthOrPort $targetRange $targetWidth]
        if {$sourceSliceWidth != $targetSliceWidth} {
            set sourceModule [dict get $sourceRecord module]
            set sourcePort [dict get $sourceRecord port]
            set targetModule [dict get $targetRecord module]
            set targetPort [dict get $targetRecord port]
            lappend errors \
                "Uma conexao com faixa possui larguras diferentes: [dict get $sourceModule instance].[dict get $sourcePort name] ($sourceSliceWidth) -> [dict get $targetModule instance].[dict get $targetPort name] ($targetSliceWidth)."
            continue
        }
        lappend sliceAssignments [dict create \
            source [::svvs::simulation_model::rangeExpression [dict get $portNets $sourceTag] $sourceRange] \
            target [::svvs::simulation_model::rangeExpression [dict get $portNets $targetTag] $targetRange] \
            width $sourceSliceWidth]
    }

    return [dict create \
        inputs $inputs outputs $outputs nets $nets portNets $portNets errors $errors \
        traces $traces signalBlocks $signalBlocks clocks $clocks \
        sliceAssignments $sliceAssignments]
}

proc ::svvs::simulation_model::connectionHasSlice {connection} {
    foreach key {fromRange toRange} {
        if {[dict exists $connection $key] && [dict get $connection $key] ne ""} {
            return 1
        }
    }
    return 0
}

proc ::svvs::simulation_model::directedConnection {connection allPorts} {
    set from [dict get $connection from]
    set to [dict get $connection to]
    set fromPort [dict get [dict get $allPorts $from] port]
    set toPort [dict get [dict get $allPorts $to] port]
    set fromRange [expr {[dict exists $connection fromRange] ? [dict get $connection fromRange] : ""}]
    set toRange [expr {[dict exists $connection toRange] ? [dict get $connection toRange] : ""}]
    if {[dict get $fromPort direction] eq "output" && [dict get $toPort direction] eq "input"} {
        return [dict create source $from target $to sourceRange $fromRange targetRange $toRange]
    }
    if {[dict get $toPort direction] eq "output" && [dict get $fromPort direction] eq "input"} {
        return [dict create source $to target $from sourceRange $toRange targetRange $fromRange]
    }
    return [dict create source $from target $to sourceRange $fromRange targetRange $toRange]
}

proc ::svvs::simulation_model::rangeWidthOrPort {range portWidth} {
    if {$range eq ""} {
        return $portWidth
    }
    if {[regexp {^\s*([0-9]+)(?:\s*:\s*([0-9]+))?\s*$} $range -> left right]} {
        if {$right eq ""} { set right $left }
        return [expr {abs($left - $right) + 1}]
    }
    return $portWidth
}

proc ::svvs::simulation_model::rangeExpression {net range} {
    if {$range eq ""} {
        return $net
    }
    return "${net}\[[string trim $range]\]"
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
    if {[dict exists $model sliceAssignments]} {
        foreach assignment [dict get $model sliceAssignments] {
            lappend lines "    assign [dict get $assignment target] = [dict get $assignment source];"
        }
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
    return [::svvs::toolchain::yosys]
}

proc ::svvs::simulation_model::sv2vExecutable {} {
    return [::svvs::toolchain::sv2v]
}

proc ::svvs::simulation_model::pythonExecutable {} {
    return [::svvs::toolchain::python]
}

proc ::svvs::simulation_model::progress {text percent} {
    if {[llength [info commands ::svvs::simulator_view::showBuildStep]]} {
        ::svvs::simulator_view::showBuildStep $text $percent
    }
}

proc ::svvs::simulation_model::buildLog {message {level info}} {
    if {[llength [info commands ::svvs::console::log]]} {
        ::svvs::console::log "Build: $message" $level
    }
}

proc ::svvs::simulation_model::quoteCommandArg {arg} {
    if {[regexp {\s|["{}]} $arg]} {
        return "\"[string map [list "\\" "\\\\" "\"" "\\\""] $arg]\""
    }
    return $arg
}

proc ::svvs::simulation_model::commandText {command} {
    set result {}
    foreach arg $command {
        lappend result [::svvs::simulation_model::quoteCommandArg $arg]
    }
    return [join $result " "]
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
    ::svvs::simulation_model::buildLog "Preparando copias normalizadas em: [file normalize $directory]"
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
        ::svvs::simulation_model::buildLog "Pacote copiado: [file normalize $source] -> [file normalize $target]"
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
        ::svvs::simulation_model::buildLog "Fonte preparada: [file normalize $source] -> [file normalize $target]"
        lappend prepared $target
    }
    return $prepared
}

proc ::svvs::simulation_model::prepare {} {
    variable buildDir
    variable topModule
    ::svvs::simulation_model::progress "Checking diagram" 8
    set model [::svvs::simulation_model::diagramModel]
    if {[llength [dict get $model errors]] > 0} {
        return [dict create ok 0 model $model message [join [dict get $model errors] "\n"]]
    }
    if {[llength [dict get $model inputs]] == 0 && [llength [dict get $model outputs]] == 0} {
        return [dict create ok 0 model $model message "Adicione pelo menos um bloco ao diagrama."]
    }

    set buildDir [::svvs::toolchain::buildDirectory]
    ::svvs::simulation_model::buildLog "Diretorio temporario da build: [file normalize $buildDir]"
    ::svvs::simulation_model::buildLog \
        "Modelo do diagrama: [llength [dict get $model inputs]] entrada(s), [llength [dict get $model outputs]] saida(s), [llength [dict get $model nets]] rede(s)."
    set topPath [file join $buildDir rtl_explorer_top.sv]
    set convertedPath [file join $buildDir rtl_explorer_design.v]
    set jsonPath [file join $buildDir netlist.json]
    set cxxrtlPath [file join $buildDir cxxrtl_model.cpp]
    set scriptPath [file join $buildDir synth.ys]
    ::svvs::simulation_model::progress "Writing top module" 16
    ::svvs::simulation_model::writeTop $topPath $model
    ::svvs::simulation_model::buildLog "Top wrapper criado: [file normalize $topPath]"

    set sourceFiles [::svvs::simulation_model::filesForDiagram]
    ::svvs::simulation_model::buildLog "Arquivos RTL usados no diagrama: [llength $sourceFiles]"
    foreach path $sourceFiles {
        ::svvs::simulation_model::buildLog "Usando RTL: [file normalize $path]"
    }
    ::svvs::simulation_model::progress "Preparing sources" 24
    set files [::svvs::simulation_model::prepareSourceFiles \
        $sourceFiles [file join $buildDir sources]]
    set lines {}
    set includeDirs {}
    foreach path $::svvs::project_tree::projectFiles {
        lappend includeDirs [file dirname $path]
    }
    set includeDirs [lsort -unique $includeDirs]
    foreach dir $includeDirs {
        ::svvs::simulation_model::buildLog "Include dir: [file normalize $dir]"
    }
    set sv2v [::svvs::simulation_model::sv2vExecutable]
    if {$sv2v eq ""} {
        return [dict create ok 0 missingTool sv2v model $model top $topPath script $scriptPath \
            message "sv2v nao foi encontrado. Instale o conversor ou adicione-o em .tools/sv2v."]
    }
    catch {file delete -force $convertedPath}
    set sv2vCommand [list $sv2v]
    foreach dir $includeDirs {
        lappend sv2vCommand "--incdir=[file normalize $dir]"
    }
    lappend sv2vCommand "--write=[file normalize $convertedPath]"
    foreach path $files { lappend sv2vCommand [file normalize $path] }
    lappend sv2vCommand [file normalize $topPath]
    ::svvs::simulation_model::progress "sv2v" 38
    ::svvs::simulation_model::buildLog "Executando sv2v: [::svvs::simulation_model::commandText $sv2vCommand]"
    if {[catch {exec {*}$sv2vCommand 2>@1} sv2vOutput]} {
        return [dict create ok 0 model $model top $topPath converted $convertedPath script $scriptPath \
            message "Falha no sv2v:\n$sv2vOutput"]
    }
    if {![file exists $convertedPath]} {
        return [dict create ok 0 model $model top $topPath converted $convertedPath script $scriptPath \
            message "O sv2v terminou sem gerar o arquivo Verilog convertido."]
    }
    ::svvs::simulation_model::buildLog "Verilog convertido criado: [file normalize $convertedPath]" ok

    ::svvs::simulation_model::progress "Writing Yosys script" 52
    lappend lines "read_verilog [::svvs::simulation_model::yosysQuote $convertedPath]"
    lappend lines "hierarchy -check -top $topModule"
    lappend lines "proc; flatten; opt; memory; opt"
    lappend lines "write_json [::svvs::simulation_model::yosysQuote $jsonPath]"
    lappend lines "write_cxxrtl -O3 -g2 [::svvs::simulation_model::yosysQuote $cxxrtlPath]"
    set handle [open $scriptPath w]
    puts $handle [join $lines "\n"]
    close $handle
    ::svvs::simulation_model::buildLog "Script Yosys criado: [file normalize $scriptPath]"
    foreach line $lines {
        ::svvs::simulation_model::buildLog "Yosys step: $line"
    }

    set yosys [::svvs::simulation_model::yosysExecutable]
    if {$yosys eq ""} {
        return [dict create ok 0 missingTool yosys model $model top $topPath converted $convertedPath script $scriptPath \
            message "Yosys nao foi encontrado. O projeto de sintese foi preparado, mas ainda nao pode ser executado."]
    }
    ::svvs::simulation_model::progress "Yosys synthesis" 66
    set yosysCommand [list $yosys -q -s $scriptPath]
    ::svvs::simulation_model::buildLog "Executando Yosys: [::svvs::simulation_model::commandText $yosysCommand]"
    if {[catch {exec $yosys -q -s $scriptPath 2>@1} output]} {
        return [dict create ok 0 model $model converted $convertedPath message "Falha na sintese Yosys:\n$output"]
    }
    ::svvs::simulation_model::progress "Netlist ready" 78
    ::svvs::simulation_model::buildLog "JSON da sintese criado: [file normalize $jsonPath]" ok
    ::svvs::simulation_model::buildLog "Modelo CXXRTL criado: [file normalize $cxxrtlPath]" ok
    return [dict create ok 1 model $model json $jsonPath cxxrtl $cxxrtlPath \
        top $topPath converted $convertedPath script $scriptPath]
}
