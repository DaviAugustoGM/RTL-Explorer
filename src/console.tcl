namespace eval ::svvs::console {
    variable widget ""
}

proc ::svvs::console::create {parent} {
    variable widget
    set frame [ttk::frame $parent -style Panel.TFrame]
    ttk::label $frame.title -text "CONSOLE" -style Section.Panel.TLabel
    text $frame.text \
        -height 7 \
        -wrap word \
        -background [::svvs::theme::color panelAlt] \
        -foreground [::svvs::theme::color text] \
        -insertbackground [::svvs::theme::color text] \
        -selectbackground [::svvs::theme::color selected] \
        -font {Consolas 9} \
        -padx 8 \
        -pady 6 \
        -spacing1 1 \
        -borderwidth 0 \
        -highlightthickness 1 \
        -highlightbackground [::svvs::theme::color border] \
        -state disabled
    ttk::scrollbar $frame.scroll -orient vertical -command "$frame.text yview"
    $frame.text configure -yscrollcommand "$frame.scroll set"

    grid $frame.title -row 0 -column 0 -columnspan 2 -sticky ew -padx 12 -pady {7 5}
    grid $frame.text -row 1 -column 0 -sticky nsew -padx {8 0} -pady {0 8}
    grid $frame.scroll -row 1 -column 1 -sticky ns -padx {0 6} -pady {0 8}
    grid columnconfigure $frame 0 -weight 1
    grid rowconfigure $frame 1 -weight 1

    set widget $frame.text
    return $frame
}

proc ::svvs::console::log {message {level info}} {
    variable widget
    if {$widget eq "" || ![winfo exists $widget]} {
        return
    }

    set ts [clock format [clock seconds] -format "%H:%M:%S"]
    $widget configure -state normal
    $widget insert end "\[$ts\] $message\n" $level
    $widget tag configure info -foreground [::svvs::theme::color text]
    $widget tag configure warn -foreground [::svvs::theme::color warning]
    $widget tag configure error -foreground [::svvs::theme::color error]
    $widget tag configure ok -foreground [::svvs::theme::color success]
    $widget see end
    $widget configure -state disabled
}
