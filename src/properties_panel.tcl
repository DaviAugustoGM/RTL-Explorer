namespace eval ::svvs::properties_panel {
    variable widget ""
}

proc ::svvs::properties_panel::create {parent} {
    variable widget
    set frame [ttk::frame $parent -style Panel.TFrame]
    ttk::label $frame.title -text "PROPERTIES" -style Section.Panel.TLabel
    text $frame.text \
        -width 30 \
        -wrap word \
        -background [::svvs::theme::color panelAlt] \
        -foreground [::svvs::theme::color text] \
        -insertbackground [::svvs::theme::color text] \
        -selectbackground [::svvs::theme::color selected] \
        -font {Consolas 9} \
        -padx 8 \
        -pady 7 \
        -spacing1 1 \
        -borderwidth 0 \
        -highlightthickness 1 \
        -highlightbackground [::svvs::theme::color border] \
        -state disabled

    grid $frame.title -row 0 -column 0 -sticky ew -padx 12 -pady {10 6}
    grid $frame.text -row 1 -column 0 -sticky nsew -padx 8 -pady {0 8}
    grid columnconfigure $frame 0 -weight 1
    grid rowconfigure $frame 1 -weight 1

    set widget $frame.text
    ::svvs::properties_panel::showWelcome
    return $frame
}

proc ::svvs::properties_panel::setText {content} {
    variable widget
    if {$widget eq "" || ![winfo exists $widget]} {
        return
    }
    $widget configure -state normal
    $widget delete 1.0 end
    $widget insert end $content
    $widget configure -state disabled
}

proc ::svvs::properties_panel::showWelcome {} {
    ::svvs::properties_panel::setText "Selecione um bloco, porta ou conexao para ver detalhes."
}

proc ::svvs::properties_panel::showModule {module} {
    set lines [list \
        "Type: Module Instance" \
        "Module: [dict get $module name]" \
        "Instance: [dict get $module instance]" \
        "" \
        "Ports:"]

    foreach port [dict get $module ports] {
        set width [dict get $port width]
        set label [dict get $port name]
        if {$width > 1} {
            set label "$label \[[expr {$width - 1}]:0\]"
        }
        lappend lines [format "%-14s %s" $label [dict get $port direction]]
    }
    if {[llength [info commands ::svvs::simulation_components::propertyLines]] > 0} {
        set lines [concat $lines [::svvs::simulation_components::propertyLines $module]]
    }

    ::svvs::properties_panel::setText [join $lines "\n"]
}

proc ::svvs::properties_panel::showPort {module port} {
    set width [dict get $port width]
    set widthText "1"
    if {$width > 1} {
        set widthText "\[[expr {$width - 1}]:0\] ($width bits)"
    }

    ::svvs::properties_panel::setText [join [list \
        "Type: Port" \
        "Module: [dict get $module name]" \
        "Instance: [dict get $module instance]" \
        "Port: [dict get $port name]" \
        "Direction: [dict get $port direction]" \
        "Width: $widthText"] "\n"]
}

proc ::svvs::properties_panel::showConnection {connection} {
    ::svvs::properties_panel::setText [join [list \
        "Type: Connection" \
        "Signal: [dict get $connection signal]" \
        "From: [dict get $connection from]" \
        "To: [dict get $connection to]" \
        "Width: [dict get $connection width]" \
        "Current value: X"] "\n"]
}
