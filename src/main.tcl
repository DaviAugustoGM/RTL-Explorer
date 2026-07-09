#!/usr/bin/env wish

package require Tk

set ::APP_DIR [file dirname [file normalize [info script]]]

source [file join $::APP_DIR toolchain.tcl]
::svvs::toolchain::activate
source [file join $::APP_DIR theme.tcl]
source [file join $::APP_DIR console.tcl]
source [file join $::APP_DIR properties_panel.tcl]
source [file join $::APP_DIR project_tree.tcl]
source [file join $::APP_DIR canvas_connections.tcl]
source [file join $::APP_DIR canvas_blocks.tcl]
source [file join $::APP_DIR fsm_viewer.tcl]
source [file join $::APP_DIR simulation_model.tcl]
source [file join $::APP_DIR simulation_components.tcl]
source [file join $::APP_DIR diagram_simulation.tcl]
source [file join $::APP_DIR simulation_backends.tcl]
source [file join $::APP_DIR simulator_view.tcl]
source [file join $::APP_DIR documentation.tcl]
source [file join $::APP_DIR sv_parser.tcl]
source [file join $::APP_DIR pdf_export.tcl]
source [file join $::APP_DIR layout.tcl]

namespace eval ::svvs {
    variable appName "RTL Explorer"
    variable state
    array set state {
        selected ""
        connectionStart ""
        dragItem ""
        dragX 0
        dragY 0
        blockSeq 0
    }
}

proc ::svvs::boot {} {
    variable appName

    wm title . $appName
    ::svvs::theme::configureScale .
    wm geometry . [::svvs::theme::initialGeometry .]
    wm minsize . [::svvs::theme::scale 980] [::svvs::theme::scale 620]

    ::svvs::theme::apply .
    ::svvs::layout::create .

    ::svvs::project_tree::closeProject
    ::svvs::console::log "RTL Explorer iniciado."
    ::svvs::console::log "Use File > Open Folder para abrir a pasta sample ou outro projeto."

    bind . <Delete> {::svvs::canvas_blocks::deleteSelected}
    bind . <Escape> {::svvs::canvas_blocks::cancelAction}
    bind . <Control-s> {::svvs::layout::saveProject}
    bind . <Control-o> {::svvs::layout::openFiles}
    bind . <Control-p> {::svvs::pdf_export::exportCurrent}
    bind . <Control-f> {::svvs::console::log "Busca acionada (placeholder)."}
    bind . <F5> {::svvs::simulator_view::run}
    wm protocol . WM_DELETE_WINDOW {
        ::svvs::simulator_view::closeProcess
        destroy .
    }
}

::svvs::boot
