namespace eval ::svvs::demo_scenarios {
    variable scenarios {}
    variable selected ""
    variable duration 500
    variable combo ""
    variable tree ""
    variable timer ""
    variable playIndex 0
    variable nameInput ""
    variable trigger "Time"
    variable clockChoice ""
    variable clockCombo ""
    variable amountWidget ""
    variable unitLabel ""
    variable waitingClock ""
    variable waitingEdge ""
    variable remainingEdges 0
}

proc ::svvs::demo_scenarios::create {parent} {
    variable combo
    variable tree
    variable duration
    variable clockCombo
    variable amountWidget
    variable unitLabel
    set frame [ttk::frame $parent.demo -style Panel.TFrame]
    pack $frame -fill both -expand 1 -pady {12 0}
    ttk::label $frame.title -text "DEMO SCENARIOS" -style Section.Panel.TLabel
    pack $frame.title -anchor w -pady {0 6}
    set bar [ttk::frame $frame.bar -style Panel.TFrame]
    pack $bar -fill x
    set combo [ttk::combobox $bar.scenario -state readonly -width 22 \
        -textvariable ::svvs::demo_scenarios::selected]
    ttk::button $bar.new -text "New" -command ::svvs::demo_scenarios::newDialog
    ttk::button $bar.capture -text "Add step" -command ::svvs::demo_scenarios::captureStep
    ttk::button $bar.play -text "Play" -command ::svvs::demo_scenarios::play
    ttk::button $bar.stop -text "Stop" -command ::svvs::demo_scenarios::stop
    ttk::button $bar.delete -text "Delete" -command ::svvs::demo_scenarios::deleteSelected
    pack $combo -side left -fill x -expand 1
    foreach widget [list $bar.new $bar.capture $bar.play $bar.stop $bar.delete] {
        pack $widget -side left -padx {4 0}
    }
    bind $combo <<ComboboxSelected>> {::svvs::demo_scenarios::refreshSteps}

    set timing [ttk::frame $frame.timing -style Panel.TFrame]
    pack $timing -fill x -pady {6 0}
    ttk::label $timing.label -text "Hold until" -style Panel.TLabel
    ttk::combobox $timing.trigger -state readonly -width 12 \
        -values {Time Rising Falling Cycles} -textvariable ::svvs::demo_scenarios::trigger
    set amountWidget [ttk::spinbox $timing.amount -from 1 -to 60000 -increment 1 -width 7 \
        -textvariable ::svvs::demo_scenarios::duration
    ]
    set unitLabel [ttk::label $timing.unit -text "ms" -style Panel.TLabel]
    set clockCombo [ttk::combobox $timing.clock -state disabled -width 22 \
        -textvariable ::svvs::demo_scenarios::clockChoice]
    pack $timing.label $timing.trigger $timing.amount $unitLabel $clockCombo \
        -side left -padx {0 6}
    bind $timing.trigger <<ComboboxSelected>> {::svvs::demo_scenarios::triggerChanged}
    ::svvs::demo_scenarios::refreshClockChoices

    set table [ttk::frame $frame.table -style Panel.TFrame]
    pack $table -fill both -expand 1 -pady {7 0}
    set tree [ttk::treeview $table.tree -columns {duration values} -show headings -height 5]
    $tree heading duration -text "Hold"
    $tree heading values -text "Inputs"
    $tree column duration -width 80 -stretch 0
    $tree column values -width 280 -stretch 1
    ttk::scrollbar $table.scroll -orient vertical -command "$tree yview"
    $tree configure -yscrollcommand "$table.scroll set"
    grid $tree -row 0 -column 0 -sticky nsew
    grid $table.scroll -row 0 -column 1 -sticky ns
    grid columnconfigure $table 0 -weight 1
    grid rowconfigure $table 0 -weight 1
    return $frame
}

proc ::svvs::demo_scenarios::refreshClockChoices {} {
    variable clockCombo
    variable clockChoice
    if {$clockCombo eq "" || ![winfo exists $clockCombo]} { return }
    set model $::svvs::simulator_view::currentModel
    if {$model eq ""} { set model [::svvs::simulation_model::diagramModel] }
    set names {}
    if {[dict exists $model clocks]} {
        foreach clockInfo [dict get $model clocks] { lappend names [dict get $clockInfo name] }
    }
    $clockCombo configure -values $names
    if {$clockChoice eq "" || [lsearch -exact $names $clockChoice] < 0} {
        set clockChoice [expr {[llength $names] ? [lindex $names 0] : ""}]
    }
}

proc ::svvs::demo_scenarios::triggerChanged {} {
    variable trigger
    variable unitLabel
    variable clockCombo
    variable duration
    variable amountWidget
    if {$trigger eq "Time"} {
        $unitLabel configure -text "ms"
        $clockCombo configure -state disabled
        $amountWidget configure -state normal
        if {$duration < 10} { set duration 500 }
    } elseif {$trigger eq "Cycles"} {
        $unitLabel configure -text "cycles"
        $clockCombo configure -state readonly
        $amountWidget configure -state normal
        if {$duration > 100} { set duration 1 }
    } else {
        $unitLabel configure -text "edge"
        $clockCombo configure -state readonly
        $amountWidget configure -state disabled
    }
    ::svvs::demo_scenarios::refreshClockChoices
}

proc ::svvs::demo_scenarios::scenarioIndex {name} {
    variable scenarios
    for {set i 0} {$i < [llength $scenarios]} {incr i} {
        if {[dict get [lindex $scenarios $i] name] eq $name} { return $i }
    }
    return -1
}

proc ::svvs::demo_scenarios::newDialog {} {
    variable nameInput
    set nameInput "Demo [expr {[llength $::svvs::demo_scenarios::scenarios] + 1}]"
    catch {destroy .scenarioName}
    toplevel .scenarioName
    wm title .scenarioName "New scenario"
    wm transient .scenarioName .
    ttk::label .scenarioName.label -text "Scenario name"
    ttk::entry .scenarioName.value -textvariable ::svvs::demo_scenarios::nameInput -width 28
    ttk::button .scenarioName.create -text "Create" -command ::svvs::demo_scenarios::commitNew
    grid .scenarioName.label -row 0 -column 0 -columnspan 2 -sticky w -padx 14 -pady {14 7}
    grid .scenarioName.value -row 1 -column 0 -padx {14 8} -pady {0 14}
    grid .scenarioName.create -row 1 -column 1 -padx {0 14} -pady {0 14}
    bind .scenarioName.value <Return> {::svvs::demo_scenarios::commitNew}
    focus .scenarioName.value
    .scenarioName.value selection range 0 end
}

proc ::svvs::demo_scenarios::commitNew {} {
    variable scenarios
    variable selected
    variable nameInput
    set name [string trim $nameInput]
    if {$name eq "" || [::svvs::demo_scenarios::scenarioIndex $name] >= 0} {
        ::svvs::console::log "Use um nome de cenario novo e nao vazio." warn
        return
    }
    lappend scenarios [dict create name $name steps {}]
    set selected $name
    destroy .scenarioName
    ::svvs::demo_scenarios::refresh
}

proc ::svvs::demo_scenarios::captureStep {} {
    variable scenarios
    variable selected
    variable duration
    variable trigger
    variable clockChoice
    if {$selected eq ""} {
        set selected "Demo 1"
        lappend scenarios [dict create name $selected steps {}]
    }
    set values {}
    set model $::svvs::simulator_view::currentModel
    if {$model eq ""} { set model [::svvs::simulation_model::diagramModel] }
    foreach signal [dict get $model inputs] {
        if {![dict exists $signal sourceKind] || [dict get $signal sourceKind] ne "input"} { continue }
        set name [dict get $signal name]
        set value [expr {[info exists ::svvs::simulator_view::signalVars($name)] ?
            $::svvs::simulator_view::signalVars($name) : [dict get $signal initialValue]}]
        dict set values $name $value
    }
    set index [::svvs::demo_scenarios::scenarioIndex $selected]
    set scenario [lindex $scenarios $index]
    set step [dict create values $values]
    switch -- $trigger {
        Rising - Falling {
            if {$clockChoice eq ""} {
                ::svvs::console::log "Adicione um bloco de clock antes de usar uma borda." warn
                return
            }
            dict set step trigger [string tolower $trigger]
            dict set step clock $clockChoice
        }
        Cycles {
            if {$clockChoice eq ""} {
                ::svvs::console::log "Adicione um bloco de clock antes de contar ciclos." warn
                return
            }
            dict set step trigger cycles
            dict set step clock $clockChoice
            dict set step cycles [expr {max(1, int($duration))}]
        }
        default {
            dict set step trigger time
            dict set step duration [expr {max(10, int($duration))}]
        }
    }
    dict lappend scenario steps $step
    set scenarios [lreplace $scenarios $index $index $scenario]
    ::svvs::demo_scenarios::refresh
    ::svvs::console::log "Passo adicionado ao cenario $selected." ok
}

proc ::svvs::demo_scenarios::play {} {
    variable selected
    variable playIndex
    set index [::svvs::demo_scenarios::scenarioIndex $selected]
    if {$index < 0 || [llength [dict get [lindex $::svvs::demo_scenarios::scenarios $index] steps]] == 0} {
        ::svvs::console::log "O cenario selecionado nao possui passos." warn
        return
    }
    ::svvs::demo_scenarios::stop
    ::svvs::simulator_view::run
    set playIndex 0
    after idle ::svvs::demo_scenarios::playNext
}

proc ::svvs::demo_scenarios::playNext {} {
    variable scenarios
    variable selected
    variable playIndex
    variable timer
    variable waitingClock
    variable waitingEdge
    variable remainingEdges
    set index [::svvs::demo_scenarios::scenarioIndex $selected]
    if {$index < 0} { return }
    set steps [dict get [lindex $scenarios $index] steps]
    if {$playIndex >= [llength $steps]} {
        set timer ""
        ::svvs::console::log "Cenario concluido: $selected" ok
        return
    }
    set step [lindex $steps $playIndex]
    dict for {name value} [dict get $step values] {
        ::svvs::simulator_view::setInputValue $name $value
    }
    incr playIndex
    set trigger [expr {[dict exists $step trigger] ? [dict get $step trigger] : "time"}]
    if {$trigger eq "time"} {
        set duration [expr {[dict exists $step duration] ? [dict get $step duration] : 500}]
        set timer [after $duration ::svvs::demo_scenarios::playNext]
    } else {
        set timer ""
        set waitingClock [dict get $step clock]
        set waitingEdge [expr {$trigger eq "falling" ? "falling" : "rising"}]
        set remainingEdges [expr {$trigger eq "cycles" ? [dict get $step cycles] : 1}]
    }
}

proc ::svvs::demo_scenarios::clockEdge {name edge} {
    variable timer
    variable waitingClock
    variable waitingEdge
    variable remainingEdges
    if {$waitingClock eq "" || $name ne $waitingClock || $edge ne $waitingEdge} { return }
    incr remainingEdges -1
    if {$remainingEdges > 0} { return }
    set waitingClock ""
    set waitingEdge ""
    set remainingEdges 0
    set timer [after idle ::svvs::demo_scenarios::playNext]
}

proc ::svvs::demo_scenarios::stop {} {
    variable timer
    variable waitingClock
    variable waitingEdge
    variable remainingEdges
    if {$timer ne ""} { after cancel $timer; set timer "" }
    set waitingClock ""
    set waitingEdge ""
    set remainingEdges 0
}

proc ::svvs::demo_scenarios::deleteSelected {} {
    variable scenarios
    variable selected
    set index [::svvs::demo_scenarios::scenarioIndex $selected]
    if {$index < 0} { return }
    set scenarios [lreplace $scenarios $index $index]
    set selected [expr {[llength $scenarios] ? [dict get [lindex $scenarios 0] name] : ""}]
    ::svvs::demo_scenarios::refresh
}

proc ::svvs::demo_scenarios::refresh {} {
    variable combo
    variable scenarios
    if {$combo ne "" && [winfo exists $combo]} {
        set names {}
        foreach scenario $scenarios { lappend names [dict get $scenario name] }
        $combo configure -values $names
    }
    ::svvs::demo_scenarios::refreshClockChoices
    ::svvs::demo_scenarios::refreshSteps
}

proc ::svvs::demo_scenarios::stepTriggerLabel {step} {
    set trigger [expr {[dict exists $step trigger] ? [dict get $step trigger] : "time"}]
    switch -- $trigger {
        rising { return "Rising: [dict get $step clock]" }
        falling { return "Falling: [dict get $step clock]" }
        cycles { return "[dict get $step cycles] cycles: [dict get $step clock]" }
        default {
            set duration [expr {[dict exists $step duration] ? [dict get $step duration] : 500}]
            return "$duration ms"
        }
    }
}

proc ::svvs::demo_scenarios::refreshSteps {} {
    variable tree
    variable scenarios
    variable selected
    if {$tree eq "" || ![winfo exists $tree]} { return }
    $tree delete [$tree children {}]
    set index [::svvs::demo_scenarios::scenarioIndex $selected]
    if {$index < 0} { return }
    set number 0
    foreach step [dict get [lindex $scenarios $index] steps] {
        incr number
        set pairs {}
        dict for {name value} [dict get $step values] { lappend pairs "$name=$value" }
        $tree insert {} end -text $number -values [list \
            [::svvs::demo_scenarios::stepTriggerLabel $step] [join $pairs {, }]]
    }
}

proc ::svvs::demo_scenarios::exportData {} {
    variable scenarios
    variable selected
    variable duration
    variable trigger
    variable clockChoice
    return [dict create scenarios $scenarios selected $selected duration $duration \
        trigger $trigger clock $clockChoice]
}

proc ::svvs::demo_scenarios::importData {data} {
    variable scenarios
    variable selected
    variable duration
    variable trigger
    variable clockChoice
    set scenarios [expr {[dict exists $data scenarios] ? [dict get $data scenarios] : {}}]
    set selected [expr {[dict exists $data selected] ? [dict get $data selected] : ""}]
    if {[dict exists $data duration]} { set duration [dict get $data duration] }
    if {[dict exists $data trigger]} { set trigger [dict get $data trigger] }
    if {[dict exists $data clock]} { set clockChoice [dict get $data clock] }
    if {$::svvs::demo_scenarios::clockCombo ne "" &&
        [winfo exists $::svvs::demo_scenarios::clockCombo]} {
        ::svvs::demo_scenarios::triggerChanged
    }
    ::svvs::demo_scenarios::refresh
}

proc ::svvs::demo_scenarios::reset {} {
    variable scenarios
    variable selected
    ::svvs::demo_scenarios::stop
    set scenarios {}
    set selected ""
    ::svvs::demo_scenarios::refresh
}
