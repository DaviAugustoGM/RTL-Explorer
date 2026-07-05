namespace eval ::svvs::layout {
    variable widgets
    variable icons
    variable tooltip ""
    variable toolbarActive
    array set widgets {}
    array set icons {}
    array set toolbarActive {}
}

proc ::svvs::layout::create {root} {
    set main [ttk::frame $root.main -style TFrame]
    pack $main -fill both -expand 1

    ::svvs::layout::createTopbar $main

    set vertical [ttk::panedwindow $main.vertical -orient vertical]
    pack $vertical -fill both -expand 1

    set work [ttk::panedwindow $vertical.work -orient horizontal]
    set waveforms [::svvs::simulator_view::createWaveformPanel $vertical.waveforms]
    set console [::svvs::console::create $vertical.console]
    $vertical add $work -weight 6
    $vertical add $waveforms -weight 2
    $vertical add $console -weight 2

    set sidebar [::svvs::layout::createSidebar $work.sidebar]
    set explorer [::svvs::project_tree::create $work.explorer]
    set center [::svvs::layout::createCenter $work.center]
    set props [::svvs::properties_panel::create $work.props]

    $work add $sidebar -weight 0
    $work add $explorer -weight 1
    $work add $center -weight 5
    $work add $props -weight 1
}

proc ::svvs::layout::createTopbar {parent} {
    variable widgets
    variable toolbarActive
    set top [ttk::frame $parent.topbar -style Topbar.TFrame]
    pack $top -side top -fill x

    foreach item {
        {"File" {::svvs::layout::showFileMenu %W}}
        {"Auto Connect" {::svvs::canvas_connections::autoConnect}}
        {"Reset" {::svvs::simulator_view::stop}}
        {"Step" {::svvs::simulator_view::step}}
        {"Run" {::svvs::simulator_view::run}}
        {"Pause" {::svvs::simulator_view::pause}}
        {"Names" {::svvs::canvas_blocks::togglePortNames}}
        {"Simple Wires" {::svvs::canvas_connections::toggleSimplified}}
    } {
        set text [lindex $item 0]
        set command [lindex $item 1]
        set name [string map {"." more " " _} [string tolower $text]]
        label $top.$name \
            -text $text \
            -background [::svvs::theme::color topbar] \
            -foreground [::svvs::theme::color muted] \
            -font {{Segoe UI} 9} \
            -padx 8 \
            -pady 5 \
            -cursor hand2
        set widgets(toolbar:$text) $top.$name
        set toolbarActive($top.$name) 0
        bind $top.$name <Enter> [list $top.$name configure \
            -background [::svvs::theme::color blockHeader] -foreground #ffffff]
        bind $top.$name <Leave> [list ::svvs::layout::restoreToolbarWidget $top.$name]
        bind $top.$name <Button-1> $command
        pack $top.$name -side left -padx 0 -pady 0
    }
    frame $parent.topbarDivider \
        -height 1 \
        -background [::svvs::theme::color border] \
        -borderwidth 0
    pack $parent.topbarDivider -side top -fill x
    ::svvs::layout::setToolbarActive "Names" 1
}

proc ::svvs::layout::restoreToolbarWidget {widget} {
    variable toolbarActive
    set active [expr {[info exists toolbarActive($widget)] && $toolbarActive($widget)}]
    $widget configure \
        -background [expr {$active ? [::svvs::theme::color selected] : [::svvs::theme::color topbar]}] \
        -foreground [expr {$active ? [::svvs::theme::color accentHover] : [::svvs::theme::color muted]}]
}

proc ::svvs::layout::setToolbarActive {text active} {
    variable widgets
    variable toolbarActive
    if {![info exists widgets(toolbar:$text)]} {
        return
    }
    set widget $widgets(toolbar:$text)
    set toolbarActive($widget) $active
    ::svvs::layout::restoreToolbarWidget $widget
}

proc ::svvs::layout::showFileMenu {widget} {
    if {[winfo exists .fileMenu]} {
        destroy .fileMenu
    }

    menu .fileMenu \
        -tearoff 0 \
        -background [::svvs::theme::color panel] \
        -foreground [::svvs::theme::color text] \
        -activebackground [::svvs::theme::color selected] \
        -activeforeground white \
        -borderwidth 1 \
        -activeborderwidth 0 \
        -font {{Segoe UI} 9}
    .fileMenu add command -label "Open Project" -command {::svvs::layout::openProject}
    .fileMenu add separator
    .fileMenu add command -label "Open Files" -command {::svvs::layout::openFiles}
    .fileMenu add command -label "Open Folder" -command {::svvs::layout::openFolder}
    .fileMenu add separator
    .fileMenu add command -label "Save Project" -command {::svvs::layout::saveProject}
    menu .fileMenu.exportPdf -tearoff 0 \
        -background [::svvs::theme::color panel] \
        -foreground [::svvs::theme::color text] \
        -activebackground [::svvs::theme::color selected] \
        -activeforeground white
    .fileMenu.exportPdf add command -label "Block Diagram..." \
        -command {::svvs::pdf_export::exportDialog blocks}
    .fileMenu.exportPdf add command -label "State Machine..." \
        -command {::svvs::pdf_export::exportDialog fsm}
    .fileMenu add cascade -label "Export PDF" -menu .fileMenu.exportPdf
    .fileMenu add command -label "Close Project" -command {::svvs::layout::closeProject}

    set x [winfo rootx $widget]
    set y [expr {[winfo rooty $widget] + [winfo height $widget]}]
    tk_popup .fileMenu $x $y
}

proc ::svvs::layout::openFolder {} {
    set dir [tk_chooseDirectory -title "Open SystemVerilog folder"]
    if {$dir eq ""} {
        return
    }

    set files [::svvs::layout::findSystemVerilogFiles $dir]
    if {[llength $files] == 0} {
        ::svvs::console::log "Nenhum arquivo .sv encontrado em: $dir" warn
        return
    }

    ::svvs::project_tree::loadProjectFiles $files [file tail $dir]
    ::svvs::console::log "Pasta carregada: $dir"
    ::svvs::console::log "Arquivos .sv encontrados: [llength $files]" ok
}

proc ::svvs::layout::openFiles {} {
    set files [tk_getOpenFile \
        -title "Open SystemVerilog files" \
        -multiple 1 \
        -filetypes {
            {"SystemVerilog files" {.sv .svh}}
            {"Verilog files" {.v .vh}}
            {"All files" {*}}
        }]
    if {[llength $files] == 0} {
        return
    }

    ::svvs::project_tree::loadProjectFiles $files "selected_files"
    ::svvs::console::log "Arquivos carregados: [llength $files]" ok
}

proc ::svvs::layout::openProject {} {
    set path [tk_getOpenFile \
        -title "Open RTL Explorer project" \
        -filetypes {
            {"RTL Explorer project" {.rtlex}}
            {"All files" {*}}
        }]
    if {$path eq ""} {
        return
    }
    ::svvs::layout::openProjectFrom $path
}

proc ::svvs::layout::openProjectFrom {path} {
    if {[catch {
        set fh [open $path r]
        fconfigure $fh -encoding utf-8
        set content [read $fh]
        close $fh
    } err]} {
        catch {close $fh}
        ::svvs::console::log "Erro ao abrir projeto: $err" error
        return 0
    }

    if {[catch {set data [dict create {*}$content]} err]} {
        ::svvs::console::log "Arquivo .rtlex invalido: $err" error
        return 0
    }
    if {![dict exists $data format] || [dict get $data format] ne "rtlex"} {
        ::svvs::console::log "Arquivo nao parece ser um projeto RTL Explorer." error
        return 0
    }

    ::svvs::canvas_blocks::clearCanvas
    if {[dict exists $data project]} {
        ::svvs::project_tree::importProjectData [dict get $data project]
    }
    if {[dict exists $data fsmView]} {
        ::svvs::fsm_viewer::importData [dict get $data fsmView]
    } else {
        ::svvs::fsm_viewer::resetEdits
        ::svvs::fsm_viewer::redraw
    }
    if {[dict exists $data diagram]} {
        ::svvs::canvas_blocks::importDiagramData [dict get $data diagram]
    }
    if {[dict exists $data connections]} {
        ::svvs::canvas_connections::importConnectionData [dict get $data connections]
    }
    if {[dict exists $data demonstrations]} {
        ::svvs::demo_scenarios::importData [dict get $data demonstrations]
    } else {
        ::svvs::demo_scenarios::reset
    }
    ::svvs::canvas_connections::refreshAll
    ::svvs::properties_panel::showWelcome
    ::svvs::console::log "Projeto aberto: $path" ok
    return 1
}

proc ::svvs::layout::findSystemVerilogFiles {dir} {
    set found {}
    foreach pattern {*.sv *.svh} {
        foreach file [glob -nocomplain -directory $dir -types f $pattern] {
            lappend found [file normalize $file]
        }
    }
    foreach child [glob -nocomplain -directory $dir -types d *] {
        set found [concat $found [::svvs::layout::findSystemVerilogFiles $child]]
    }
    return [lsort -unique $found]
}

proc ::svvs::layout::saveProject {} {
    set path [tk_getSaveFile \
        -title "Save RTL Explorer project" \
        -defaultextension ".rtlex" \
        -filetypes {
            {"RTL Explorer project" {.rtlex}}
            {"All files" {*}}
        }]
    if {$path eq ""} {
        return
    }

    if {[string tolower [file extension $path]] ne ".rtlex"} {
        append path ".rtlex"
    }
    ::svvs::layout::saveProjectTo $path
}

proc ::svvs::layout::saveProjectTo {path} {
    set data [dict create \
        format rtlex \
        version 1 \
        savedAt [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S"] \
        project [::svvs::project_tree::exportProjectData] \
        fsmView [::svvs::fsm_viewer::exportData] \
        diagram [::svvs::canvas_blocks::exportDiagramData] \
        connections [::svvs::canvas_connections::exportConnectionData] \
        demonstrations [::svvs::demo_scenarios::exportData]]

    if {[catch {
        set fh [open $path w]
        fconfigure $fh -encoding utf-8 -translation lf
        puts $fh $data
        close $fh
    } err]} {
        catch {close $fh}
        ::svvs::console::log "Erro ao salvar projeto: $err" error
        return 0
    }

    ::svvs::console::log "Projeto salvo: $path" ok
    return 1
}

proc ::svvs::layout::closeProject {} {
    ::svvs::simulator_view::closeProcess
    ::svvs::demo_scenarios::reset
    ::svvs::project_tree::closeProject
    ::svvs::canvas_blocks::clearCanvas
    ::svvs::properties_panel::showWelcome
    ::svvs::simulator_view::refreshSignals
    ::svvs::console::log "Projeto fechado."
}

proc ::svvs::layout::createSidebar {path} {
    variable icons
    variable widgets
    set frame [ttk::frame $path -style Sidebar.TFrame -width 54]
    pack propagate $frame 0

    ::svvs::layout::loadIcons

    set modes [list \
        [list project "Projeto"] \
        [list blocks "Blocos"] \
        [list fsm "Maquinas de estado"] \
        [list simulation "Simulacao"] \
        [list documentation "Documentacao"]]

    foreach mode $modes {
        set key [lindex $mode 0]
        set name [lindex $mode 1]
        set button $frame.$key
        button $button \
            -image $icons($key) \
            -command [list ::svvs::layout::selectMode $name] \
            -background [::svvs::theme::color sidebar] \
            -activebackground [::svvs::theme::color topbar] \
            -relief flat \
            -borderwidth 0 \
            -highlightthickness 1 \
            -highlightbackground [::svvs::theme::color sidebar] \
            -width 42 \
            -height 42 \
            -cursor hand2
        bind $button <Enter> [list ::svvs::layout::showTooltip $button $name]
        bind $button <Leave> {::svvs::layout::hideTooltip}
        set widgets(sidebar:$key) $button
        pack $button -side top -padx 6 -pady {8 0}
    }

    ::svvs::layout::setSidebarActive project

    return $frame
}

proc ::svvs::layout::setSidebarActive {activeKey} {
    variable widgets
    foreach key {project blocks fsm simulation documentation} {
        if {![info exists widgets(sidebar:$key)]} {
            continue
        }
        set button $widgets(sidebar:$key)
        set active [expr {$key eq $activeKey}]
        $button configure \
            -background [expr {$active ? [::svvs::theme::color blockHeader] : [::svvs::theme::color sidebar]}] \
            -highlightbackground [expr {$active ? [::svvs::theme::color accent] : [::svvs::theme::color sidebar]}]
    }
}

proc ::svvs::layout::loadIcons {} {
    variable icons

    foreach item {
        {project project.png}
        {blocks blocks.png}
        {fsm fsm.png}
        {simulation simulation.png}
        {documentation documentation.png}
    } {
        set key [lindex $item 0]
        set file [file join [file dirname $::APP_DIR] assets icons [lindex $item 1]]
        if {![info exists icons($key)]} {
            set raw [image create photo -file $file]
            set img [image create photo]
            $img copy $raw -subsample 4 4
            image delete $raw
            set icons($key) $img
        }
    }
}

proc ::svvs::layout::showTooltip {widget text} {
    variable tooltip

    ::svvs::layout::hideTooltip
    set x [expr {[winfo rootx $widget] + [winfo width $widget] + 10}]
    set y [expr {[winfo rooty $widget] + 8}]
    set tooltip .svvsTooltip

    toplevel $tooltip -background [::svvs::theme::color border]
    wm overrideredirect $tooltip 1
    wm geometry $tooltip +$x+$y
    label $tooltip.label \
        -text $text \
        -background [::svvs::theme::color blockHeader] \
        -foreground [::svvs::theme::color text] \
        -font {{Segoe UI} 9} \
        -padx 9 \
        -pady 5
    pack $tooltip.label -padx 1 -pady 1
}

proc ::svvs::layout::hideTooltip {} {
    variable tooltip
    if {$tooltip ne "" && [winfo exists $tooltip]} {
        destroy $tooltip
    }
    set tooltip ""
}

proc ::svvs::layout::selectMode {name} {
    variable widgets
    if {[info exists widgets(notebook)]} {
        switch -glob -- $name {
            "Projeto" {
                ::svvs::layout::setSidebarActive project
                ::svvs::project_tree::showProject
                $widgets(notebook) select $widgets(canvasTab)
            }
            "Blocos" {
                ::svvs::layout::setSidebarActive blocks
                ::svvs::project_tree::showBlockLibrary
                $widgets(notebook) select $widgets(canvasTab)
            }
            "Maquinas*" {
                ::svvs::layout::setSidebarActive fsm
                $widgets(notebook) select $widgets(fsmTab)
            }
            "Simulacao" {
                ::svvs::layout::setSidebarActive simulation
                $widgets(notebook) select $widgets(simTab)
            }
            "Documentacao" {
                ::svvs::layout::setSidebarActive documentation
                $widgets(notebook) select $widgets(docTab)
            }
        }
    }
    ::svvs::console::log "Modo selecionado: $name"
}

proc ::svvs::layout::showFsm {fsm} {
    variable widgets
    ::svvs::fsm_viewer::showFSM $fsm
    ::svvs::layout::setSidebarActive fsm
    if {[info exists widgets(notebook)] && [info exists widgets(fsmTab)]} {
        $widgets(notebook) select $widgets(fsmTab)
    }
}

proc ::svvs::layout::showEmptyFsm {moduleName} {
    variable widgets
    ::svvs::fsm_viewer::showEmpty "No state machine detected in $moduleName"
    ::svvs::layout::setSidebarActive fsm
    if {[info exists widgets(notebook)] && [info exists widgets(fsmTab)]} {
        $widgets(notebook) select $widgets(fsmTab)
    }
}

proc ::svvs::layout::createCenter {path} {
    variable widgets
    set notebook [ttk::notebook $path]
    set widgets(notebook) $notebook

    set canvasTab [ttk::frame $notebook.canvasTab -style TFrame]
    set fsmTab [ttk::frame $notebook.fsmTab -style TFrame]
    set simTab [ttk::frame $notebook.simTab -style TFrame]
    set docTab [ttk::frame $notebook.docTab -style TFrame]

    set widgets(canvasTab) $canvasTab
    set widgets(fsmTab) $fsmTab
    set widgets(simTab) $simTab
    set widgets(docTab) $docTab

    set canvas [::svvs::canvas_blocks::create $canvasTab]
    pack $canvas -fill both -expand 1

    ::svvs::fsm_viewer::create $fsmTab
    ::svvs::simulator_view::create $simTab
    ::svvs::documentation::create $docTab

    $notebook add $canvasTab -text "Diagram"
    $notebook add $fsmTab -text "FSM"
    $notebook add $simTab -text "Simulation"
    $notebook add $docTab -text "Documentation"
    bind $notebook <<NotebookTabChanged>> +{::svvs::simulator_view::refreshSignals}

    return $notebook
}
