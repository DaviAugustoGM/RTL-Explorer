namespace eval ::svvs::theme {
    variable colors
    array set colors {
        bg #181a1e
        panel #22252a
        panelAlt #1d2024
        topbar #292c31
        sidebar #15171a
        text #d9dee7
        muted #94a0ad
        accent #39a6d3
        accentHover #52b9e2
        block #2b2f35
        blockHeader #343941
        selected #294b5f
        border #383d45
        error #e06c75
        warning #e5c07b
        success #7fb069
        portIn #58b8c7
        portOut #e6a07b
        wire #969fa9
    }
}

proc ::svvs::theme::color {name} {
    variable colors
    return $colors($name)
}

proc ::svvs::theme::apply {root} {
    variable colors

    ttk::style theme use clam
    $root configure -background $colors(bg)

    option add *Font {{Segoe UI} 9}
    option add *Foreground $colors(text)
    option add *Background $colors(bg)
    option add *insertBackground $colors(text)

    ttk::style configure . \
        -background $colors(bg) \
        -foreground $colors(text) \
        -fieldbackground $colors(panel) \
        -bordercolor $colors(border) \
        -lightcolor $colors(border) \
        -darkcolor $colors(border) \
        -troughcolor $colors(panel) \
        -arrowcolor $colors(text)

    ttk::style configure TFrame -background $colors(bg)
    ttk::style configure Panel.TFrame -background $colors(panel)
    ttk::style configure Topbar.TFrame -background $colors(topbar)
    ttk::style configure Sidebar.TFrame -background $colors(sidebar)
    ttk::style configure TLabel -background $colors(bg) -foreground $colors(text)
    ttk::style configure Panel.TLabel -background $colors(panel) -foreground $colors(text)
    ttk::style configure Muted.Panel.TLabel \
        -background $colors(panel) -foreground $colors(muted) \
        -font {{Segoe UI} 9}
    ttk::style configure Section.Panel.TLabel \
        -background $colors(panel) -foreground $colors(accent) \
        -font {{Segoe UI} 9 bold}

    ttk::style configure TButton \
        -background $colors(topbar) \
        -foreground $colors(text) \
        -bordercolor $colors(border) \
        -padding {9 4}
    ttk::style map TButton \
        -background [list active $colors(accent) pressed $colors(selected)] \
        -foreground [list active white pressed white]

    ttk::style configure Tool.TButton \
        -background $colors(topbar) \
        -foreground $colors(text) \
        -borderwidth 0 \
        -relief flat \
        -padding {8 2} \
        -anchor center
    ttk::style map Tool.TButton \
        -background [list active $colors(blockHeader) pressed $colors(selected)] \
        -foreground [list active white pressed white] \
        -relief [list active flat pressed flat]
    ttk::style configure Mode.TButton -padding {4 8} -anchor center

    ttk::style configure TNotebook -background $colors(bg) -borderwidth 0 -tabmargins 0
    ttk::style configure TNotebook.Tab \
        -background $colors(panel) \
        -foreground $colors(muted) \
        -borderwidth 0 \
        -padding {13 7} \
        -font {{Segoe UI} 9}
    ttk::style map TNotebook.Tab \
        -background [list selected $colors(bg) active $colors(topbar)] \
        -foreground [list selected $colors(accent) active $colors(text)]

    ttk::style configure Treeview \
        -background $colors(panel) \
        -fieldbackground $colors(panel) \
        -foreground $colors(text) \
        -borderwidth 0 \
        -rowheight 23 \
        -font {{Segoe UI} 9}
    ttk::style configure Treeview.Heading \
        -background $colors(topbar) \
        -foreground $colors(text)
    ttk::style map Treeview \
        -background [list selected $colors(selected)] \
        -foreground [list selected white]

    ttk::style configure TPanedwindow -background $colors(border) -sashwidth 1
    ttk::style configure TScrollbar \
        -background $colors(blockHeader) \
        -troughcolor $colors(panelAlt) \
        -bordercolor $colors(panelAlt) \
        -arrowcolor $colors(muted) \
        -width 10
}
