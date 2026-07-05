namespace eval ::svvs::project_tree {
    variable widget ""
    variable titleWidget ""
    variable sampleModules {}
    variable projectFiles {}
    variable projectName "rtl_project"
    variable projectOpen 1
    variable fsms {}
    variable libraryModules
    variable nodeModules
    variable projectNodeModules
    variable projectFileModules
    variable nodeFsms
    variable icons
    variable dragModule ""
    array set libraryModules {}
    array set nodeModules {}
    array set projectNodeModules {}
    array set projectFileModules {}
    array set nodeFsms {}
    array set icons {}
}

proc ::svvs::project_tree::create {parent} {
    variable widget
    variable titleWidget
    ::svvs::project_tree::loadIcons
    set frame [ttk::frame $parent -style Panel.TFrame]
    ttk::label $frame.title -text "EXPLORER" -style Section.Panel.TLabel
    ttk::treeview $frame.tree -show tree -selectmode browse
    ttk::scrollbar $frame.scroll -orient vertical -command "$frame.tree yview"
    $frame.tree configure -yscrollcommand "$frame.scroll set"

    grid $frame.title -row 0 -column 0 -columnspan 2 -sticky ew -padx 12 -pady {10 6}
    grid $frame.tree -row 1 -column 0 -sticky nsew -padx {8 0} -pady {0 8}
    grid $frame.scroll -row 1 -column 1 -sticky ns -padx {0 6} -pady {0 8}
    grid columnconfigure $frame 0 -weight 1
    grid rowconfigure $frame 1 -weight 1

    set widget $frame.tree
    set titleWidget $frame.title
    bind $widget <<TreeviewSelect>> {::svvs::project_tree::onSelect}
    bind $widget <ButtonPress-1> {::svvs::project_tree::startDrag %x %y}
    bind $widget <ButtonRelease-1> {::svvs::project_tree::finishDrag %X %Y}
    bind $widget <Double-1> {::svvs::project_tree::addSelectedToCanvas}
    return $frame
}

proc ::svvs::project_tree::loadIcons {} {
    variable icons

    foreach item {
        {folder project.png}
        {block blocks.png}
    } {
        set key [lindex $item 0]
        set file [file join [file dirname $::APP_DIR] assets icons [lindex $item 1]]
        if {![info exists icons($key)] && [file exists $file]} {
            set raw [image create photo -file $file]
            set img [image create photo]
            $img copy $raw -subsample 6 6
            image delete $raw
            set icons($key) $img
        }
    }
}

proc ::svvs::project_tree::icon {name} {
    variable icons
    if {[info exists icons($name)]} {
        return $icons($name)
    }
    return ""
}

proc ::svvs::project_tree::loadSamples {modules} {
    variable widget
    variable sampleModules
    variable projectFiles
    variable projectName
    variable projectOpen
    variable fsms
    variable nodeFsms
    set projectFiles {}
    set projectName "rtl_project"
    set projectOpen 1
    set sampleModules $modules
    set fsms {}
    ::svvs::project_tree::showProject
}

proc ::svvs::project_tree::showProject {} {
    variable widget
    variable titleWidget
    variable sampleModules
    variable projectFiles
    variable projectName
    variable projectOpen
    variable fsms
    variable nodeFsms
    variable projectNodeModules
    variable projectFileModules
    variable nodeModules
    variable libraryModules
    if {$widget eq "" || ![winfo exists $widget]} {
        return
    }

    if {$titleWidget ne "" && [winfo exists $titleWidget]} {
        $titleWidget configure -text "EXPLORER"
    }

    $widget delete [$widget children {}]
    array unset nodeFsms
    array set nodeFsms {}
    array unset projectNodeModules
    array set projectNodeModules {}
    array unset projectFileModules
    array set projectFileModules {}
    # Tree item ids are reused after changing sidebar modes. Clear library-only
    # mappings so a project file cannot be mistaken for a draggable block.
    array unset nodeModules
    array set nodeModules {}
    array unset libraryModules
    array set libraryModules {}
    set folderIcon [::svvs::project_tree::icon folder]
    set blockIcon [::svvs::project_tree::icon block]

    set root [$widget insert {} end -text $projectName -open 1 -image $folderIcon]

    if {!$projectOpen} {
        $widget selection remove [$widget selection]
        return
    }

    set files [$widget insert $root end -text "files" -open 1 -image $folderIcon]
    set modulesNode [$widget insert $root end -text "modules" -open 1 -image $folderIcon]
    set signalsNode [$widget insert $root end -text "signals" -open 0 -image $folderIcon]
    set fsmNode [$widget insert $root end -text "state machines" -open 0 -image $folderIcon]

    if {[llength $projectFiles] > 0} {
        foreach file $projectFiles {
            set fileItem [$widget insert $files end -text [file tail $file]]
            set moduleNames {}
            foreach module $sampleModules {
                set matches 0
                if {[dict exists $module sourcePath]} {
                    set matches [expr {[file normalize [dict get $module sourcePath]] eq [file normalize $file]}]
                } elseif {[file rootname [file tail $file]] eq [dict get $module name]} {
                    set matches 1
                }
                if {$matches} { lappend moduleNames [dict get $module name] }
            }
            if {[llength $moduleNames] > 0} { set projectFileModules($fileItem) $moduleNames }
        }
    } else {
        $widget insert $files end -text "top.sv"
        $widget insert $files end -text "uart_rx.sv"
        $widget insert $files end -text "fifo_sync.sv"
        $widget insert $files end -text "uart_tx.sv"
    }

    foreach module $sampleModules {
        set modNode [$widget insert $modulesNode end -text [dict get $module name] -open 1 -values [dict get $module name] -image $blockIcon]
        set projectNodeModules($modNode) $module
        set inNode [$widget insert $modNode end -text "inputs" -open 0 -image $folderIcon]
        set outNode [$widget insert $modNode end -text "outputs" -open 0 -image $folderIcon]
        foreach port [dict get $module ports] {
            set text [dict get $port name]
            set width [dict get $port width]
            if {$width > 1} {
                append text " \[[expr {$width - 1}]:0\]"
            }
            if {[dict get $port direction] eq "input"} {
                $widget insert $inNode end -text $text
            } else {
                $widget insert $outNode end -text $text
            }
            $widget insert $signalsNode end -text "[dict get $module name].[dict get $port name]"
        }
    }

    foreach fsm $fsms {
        set item [$widget insert $fsmNode end \
            -text [dict get $fsm name] \
            -values [dict get $fsm module] \
            -image $blockIcon]
        set nodeFsms($item) $fsm
    }
}

proc ::svvs::project_tree::loadProjectFiles {files name} {
    variable projectFiles
    variable projectName
    variable sampleModules
    variable projectOpen
    variable fsms

    ::svvs::fsm_viewer::resetEdits

    set projectFiles {}
    foreach file $files {
        lappend projectFiles [file normalize $file]
    }
    set projectName $name
    set projectOpen 1

    set parsedModules [::svvs::sv_parser::parseModulesFromFiles $projectFiles]
    if {[llength $parsedModules] > 0} {
        set sampleModules $parsedModules
        ::svvs::console::log "Modulos detectados: [llength $parsedModules]" ok
    } else {
        set sampleModules {}
        ::svvs::console::log "Nenhum modulo detectado nos arquivos selecionados." warn
    }

    set fsms [::svvs::sv_parser::parseFsmsFromFiles $projectFiles]
    if {[llength $fsms] > 0} {
        ::svvs::console::log "Maquinas de estado detectadas: [llength $fsms]" ok
        ::svvs::fsm_viewer::showFSM [lindex $fsms 0]
    } else {
        ::svvs::console::log "Nenhuma maquina de estado detectada." warn
        ::svvs::fsm_viewer::showEmpty
    }

    ::svvs::project_tree::showProject
}

proc ::svvs::project_tree::closeProject {} {
    variable projectFiles
    variable projectName
    variable sampleModules
    variable projectOpen
    variable fsms
    variable libraryModules
    variable nodeModules
    variable projectNodeModules
    variable projectFileModules

    set projectFiles {}
    set projectName "no_project"
    set sampleModules {}
    set projectOpen 0
    set fsms {}
    ::svvs::fsm_viewer::resetEdits
    array unset libraryModules
    array unset nodeModules
    array set libraryModules {}
    array set nodeModules {}
    array unset projectNodeModules
    array set projectNodeModules {}
    array unset projectFileModules
    array set projectFileModules {}
    ::svvs::project_tree::showProject
    ::svvs::fsm_viewer::showEmpty
}

proc ::svvs::project_tree::exportProjectData {} {
    variable projectFiles
    variable projectName
    variable projectOpen
    variable sampleModules
    variable fsms

    return [dict create \
        open $projectOpen \
        name $projectName \
        files $projectFiles \
        modules $sampleModules \
        fsms $fsms]
}

proc ::svvs::project_tree::importProjectData {data} {
    variable projectFiles
    variable projectName
    variable projectOpen
    variable sampleModules
    variable fsms

    set projectOpen 1
    if {[dict exists $data open]} {
        set projectOpen [dict get $data open]
    }
    set projectName "rtl_project"
    if {[dict exists $data name]} {
        set projectName [dict get $data name]
    }
    set projectFiles {}
    if {[dict exists $data files]} {
        set projectFiles [dict get $data files]
    }
    set sampleModules {}
    if {[dict exists $data modules]} {
        set sampleModules [dict get $data modules]
    }
    set fsms {}
    if {[llength $projectFiles] > 0} {
        set fsms [::svvs::sv_parser::parseFsmsFromFiles $projectFiles]
    }
    if {[llength $fsms] == 0 && [dict exists $data fsms]} {
        set fsms [dict get $data fsms]
    }
    ::svvs::project_tree::showProject
    if {[llength $fsms] > 0} {
        ::svvs::fsm_viewer::showFSM [lindex $fsms 0]
    } else {
        ::svvs::fsm_viewer::showEmpty
    }
}

proc ::svvs::project_tree::showBlockLibrary {} {
    variable widget
    variable titleWidget
    variable sampleModules
    variable libraryModules
    variable nodeModules
    variable projectNodeModules
    variable projectFileModules
    variable nodeFsms
    set folderIcon [::svvs::project_tree::icon folder]

    if {$widget eq "" || ![winfo exists $widget]} {
        return
    }

    if {$titleWidget ne "" && [winfo exists $titleWidget]} {
        $titleWidget configure -text "BLOCKS"
    }

    array unset libraryModules
    array unset nodeModules
    array unset projectNodeModules
    array unset projectFileModules
    array unset nodeFsms
    array set libraryModules {}
    array set nodeModules {}
    array set projectNodeModules {}
    array set projectFileModules {}
    array set nodeFsms {}

    $widget delete [$widget children {}]
    set root [$widget insert {} end -text "Component Library" -open 1 -image $folderIcon]
    set userFolder [$widget insert $root end -text "User modules" -open 1 -image $folderIcon]
    set builtinFolder [$widget insert $root end -text "Built-in blocks" -open 1 -image $folderIcon]
    set sourcesFolder [$widget insert $builtinFolder end -text "Sources" -open 1 -image $folderIcon]
    set simulationFolder [$widget insert $builtinFolder end -text "Simulation I/O" -open 1 -image $folderIcon]
    set logicFolder [$widget insert $builtinFolder end -text "Logic" -open 1 -image $folderIcon]
    set storageFolder [$widget insert $builtinFolder end -text "Storage" -open 1 -image $folderIcon]

    foreach module $sampleModules {
        ::svvs::project_tree::addLibraryItem $userFolder $module
    }

    foreach module [::svvs::project_tree::builtinModules sources] {
        ::svvs::project_tree::addLibraryItem $sourcesFolder $module
    }
    foreach module [::svvs::project_tree::builtinModules simulation] {
        ::svvs::project_tree::addLibraryItem $simulationFolder $module
    }
    foreach module [::svvs::project_tree::builtinModules logic] {
        ::svvs::project_tree::addLibraryItem $logicFolder $module
    }
    foreach module [::svvs::project_tree::builtinModules storage] {
        ::svvs::project_tree::addLibraryItem $storageFolder $module
    }

    ::svvs::console::log "Biblioteca de blocos pronta. Arraste um item para o canvas ou use duplo clique."
}

proc ::svvs::project_tree::builtinModules {group} {
    switch -- $group {
        sources {
            return [list \
                [dict create name reset_pulse instance u_reset ports [list \
                    [dict create name rst_n direction output width 1]]] \
                [dict create name constant instance u_const ports [list \
                    [dict create name value direction output width 1]]]]
        }
        simulation {
            return [list \
                [dict create name input_signal instance input simulationKind input \
                    builtin 1 simulationConfig [dict create value 0 base bin trace 1 bitWidth 1 clickAction edit pulseMs 100 label "" nameAssigned 0] ports [list \
                    [dict create name out direction output width 1]]] \
                [dict create name output_probe instance probe simulationKind probe \
                    builtin 1 simulationConfig [dict create base hex trace 1 bitWidth 1 valueMap {} label "" nameAssigned 0] ports [list \
                    [dict create name in direction input width 1]]] \
                [dict create name clock_generator instance clock simulationKind clock \
                    builtin 1 simulationConfig [dict create frequency 1.0 trace 1 bitWidth 1 label "" nameAssigned 0] ports [list \
                    [dict create name clk direction output width 1]]]]
        }
        logic {
            return [list \
                [dict create name and_gate instance u_and ports [list \
                    [dict create name a direction input width 1] \
                    [dict create name b direction input width 1] \
                    [dict create name y direction output width 1]]] \
                [dict create name or_gate instance u_or ports [list \
                    [dict create name a direction input width 1] \
                    [dict create name b direction input width 1] \
                    [dict create name y direction output width 1]]] \
                [dict create name mux2 instance u_mux2 ports [list \
                    [dict create name a direction input width 8] \
                    [dict create name b direction input width 8] \
                    [dict create name sel direction input width 1] \
                    [dict create name y direction output width 8]]]]
        }
        storage {
            return [list \
                [dict create name register instance u_reg ports [list \
                    [dict create name clk direction input width 1] \
                    [dict create name rst_n direction input width 1] \
                    [dict create name d direction input width 8] \
                    [dict create name q direction output width 8]]] \
                [dict create name counter instance u_counter ports [list \
                    [dict create name clk direction input width 1] \
                    [dict create name rst_n direction input width 1] \
                    [dict create name en direction input width 1] \
                    [dict create name count direction output width 8]]]]
        }
    }
    return {}
}

proc ::svvs::project_tree::addLibraryItem {parent module} {
    variable widget
    variable libraryModules
    variable nodeModules
    set blockIcon [::svvs::project_tree::icon block]

    set name [dict get $module name]
    set item [$widget insert $parent end -text $name -image $blockIcon]
    set libraryModules($name) $module
    set nodeModules($item) $module
}

proc ::svvs::project_tree::onSelect {} {
    variable widget
    variable nodeModules
    variable nodeFsms
    variable projectNodeModules
    variable projectFileModules
    variable fsms
    set item [lindex [$widget selection] 0]
    if {$item eq ""} {
        return
    }
    if {[info exists nodeModules($item)]} {
        set module $nodeModules($item)
        ::svvs::properties_panel::showModule $module
    }
    if {[info exists projectNodeModules($item)]} {
        set module $projectNodeModules($item)
        ::svvs::properties_panel::showModule $module
        set moduleName [dict get $module name]
        set matchingFsm ""
        foreach fsm $fsms {
            if {[dict get $fsm module] eq $moduleName} {
                set matchingFsm $fsm
                break
            }
        }
        if {$matchingFsm eq ""} {
            ::svvs::layout::showEmptyFsm $moduleName
        } else {
            ::svvs::layout::showFsm $matchingFsm
        }
    }
    if {[info exists projectFileModules($item)]} {
        set moduleNames $projectFileModules($item)
        set matchingFsm ""
        foreach fsm $fsms {
            if {[lsearch -exact $moduleNames [dict get $fsm module]] >= 0} {
                set matchingFsm $fsm
                break
            }
        }
        if {$matchingFsm eq ""} {
            ::svvs::layout::showEmptyFsm [$widget item $item -text]
        } else {
            ::svvs::layout::showFsm $matchingFsm
        }
    }
    if {[info exists nodeFsms($item)]} {
        ::svvs::layout::showFsm $nodeFsms($item)
    }
    ::svvs::console::log "Explorer: [$widget item $item -text]"
}

proc ::svvs::project_tree::startDrag {x y} {
    variable widget
    variable nodeModules
    variable dragModule

    set item [$widget identify row $x $y]
    set dragModule ""
    if {$item ne "" && [info exists nodeModules($item)]} {
        set dragModule $nodeModules($item)
    }
}

proc ::svvs::project_tree::finishDrag {rootX rootY} {
    variable dragModule
    if {$dragModule eq ""} {
        return
    }

    if {[::svvs::canvas_blocks::containsScreenPoint $rootX $rootY]} {
        ::svvs::canvas_blocks::addModuleAtScreenPoint $dragModule $rootX $rootY
        ::svvs::console::log "Bloco adicionado ao canvas: [dict get $dragModule name]" ok
    }
    set dragModule ""
}

proc ::svvs::project_tree::addSelectedToCanvas {} {
    variable widget
    variable nodeModules
    set item [lindex [$widget selection] 0]
    if {$item eq "" || ![info exists nodeModules($item)]} {
        return
    }
    ::svvs::canvas_blocks::addModuleAtVisibleCenter $nodeModules($item)
    ::svvs::console::log "Bloco adicionado ao canvas: [dict get $nodeModules($item) name]" ok
}
