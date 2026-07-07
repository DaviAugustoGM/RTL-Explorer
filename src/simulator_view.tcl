namespace eval ::svvs::simulator_view {
    variable frame ""
    variable inputPanel ""
    variable outputPanel ""
    variable waveform ""
    variable statusLabel ""
    variable cycleLabel ""
    variable pauseButton ""
    variable process ""
    variable lastBuildResult ""
    variable lastBackend ""
    variable running 0
    variable timer ""
    variable speed 4
    variable cycle 0
    variable currentModel ""
    variable clockSignal ""
    variable signalVars
    variable valueLabels
    variable signalWidths
    variable history
    variable clockStates
    variable clockNext
    variable fsmWatches
    variable simulationStartTime 0
    variable lastSampleTime 0
    variable waveformWindowMs 8000
    variable waveformsEnabled 1
    array set signalVars {}
    array set valueLabels {}
    array set signalWidths {}
    array set history {}
    array set clockStates {}
    array set clockNext {}
    array set fsmWatches {}
}

proc ::svvs::simulator_view::toggleWaveforms {} {
    variable waveformsEnabled
    set waveformsEnabled [expr {!$waveformsEnabled}]
    ::svvs::layout::setToolbarActive "Waveforms" $waveformsEnabled
    if {$waveformsEnabled} {
        ::svvs::simulator_view::clearWaveformHistory
        ::svvs::console::log "Waveforms ativadas."
    } else {
        ::svvs::simulator_view::clearWaveformHistory
        ::svvs::console::log "Waveforms desativadas para economizar recursos."
    }
    ::svvs::simulator_view::drawWaveforms
}

proc ::svvs::simulator_view::create {parent} {
    variable frame
    variable inputPanel
    variable outputPanel
    variable statusLabel
    variable cycleLabel
    variable pauseButton

    set frame [ttk::frame $parent.inner -style TFrame]
    pack $frame -fill both -expand 1

    set header [ttk::frame $frame.header -style Panel.TFrame -padding {14 10}]
    pack $header -side top -fill x
    ttk::label $header.title -text "Live simulation" -style Section.Panel.TLabel
    ttk::label $header.subtitle -text "sv2v + Yosys, selectable simulation engines" -style Muted.Panel.TLabel
    pack $header.title -side left
    pack $header.subtitle -side left -padx {10 0}

    set controls [ttk::frame $frame.controls -style Topbar.TFrame -padding {10 7}]
    pack $controls -side top -fill x
    ttk::button $controls.run -text "Run" -style Tool.TButton \
        -command ::svvs::simulator_view::run
    ttk::button $controls.buildRun -text "Build and Run" -style Tool.TButton \
        -command ::svvs::simulator_view::buildAndRun
    ttk::button $controls.pause -text "Pause" -style Tool.TButton \
        -command ::svvs::simulator_view::pause
    ttk::button $controls.stop -text "Stop" -style Tool.TButton \
        -command ::svvs::simulator_view::stop
    set pauseButton $controls.pause
    foreach widget [list $controls.run $controls.buildRun $controls.pause $controls.stop] {
        pack $widget -side left -padx {0 3}
    }
    ttk::label $controls.engineLabel -text "Engine" -style Muted.Topbar.TLabel
    ttk::combobox $controls.engine -state readonly -width 11 \
        -values {Automatic CXXRTL Icarus Python} \
        -textvariable ::svvs::simulation_backends::selectedEngine
    pack $controls.engineLabel -side left -padx {14 5}
    pack $controls.engine -side left
    bind $controls.engine <<ComboboxSelected>> {::svvs::simulator_view::engineChanged}
    set cycleLabel [label $controls.cycle -text "Cycle 0" \
        -background [::svvs::theme::color topbar] -foreground [::svvs::theme::color text]]
    pack $cycleLabel -side right -padx 10
    set statusLabel [label $controls.status -text "NOT BUILT" -background #51462d \
        -foreground [::svvs::theme::color warning] -font {{Segoe UI} 8 bold} -padx 8 -pady 3]
    pack $statusLabel -side right

    # Signal state is still maintained for the diagram and waveforms, but the
    # Simulation tab is intentionally limited to build/runtime configuration.
    set inputPanel [ttk::frame $frame.inputState]
    set outputPanel [ttk::frame $frame.outputState]

    after idle ::svvs::simulator_view::refreshSignals
    return $frame
}

proc ::svvs::simulator_view::createWaveformPanel {parent} {
    variable waveform
    set frame [ttk::frame $parent -style Panel.TFrame]
    set waveform [canvas $frame.canvas -background [::svvs::theme::color bg] \
        -height 150 -highlightthickness 1 \
        -highlightbackground [::svvs::theme::color border] -borderwidth 0]
    ttk::scrollbar $frame.scroll -orient vertical -command "$waveform yview"
    $waveform configure -yscrollcommand "$frame.scroll set"
    grid $waveform -row 0 -column 0 -sticky nsew -padx {8 0} -pady 6
    grid $frame.scroll -row 0 -column 1 -sticky ns -padx {0 6} -pady 6
    grid columnconfigure $frame 0 -weight 1
    grid rowconfigure $frame 0 -weight 1
    bind $waveform <Configure> {::svvs::simulator_view::drawWaveforms}
    bind $waveform <MouseWheel> {::svvs::simulator_view::scrollWaveforms %D}
    bind $waveform <Button-4> {::svvs::simulator_view::scrollWaveforms 1}
    bind $waveform <Button-5> {::svvs::simulator_view::scrollWaveforms -1}
    after idle ::svvs::simulator_view::drawWaveforms
    return $frame
}

proc ::svvs::simulator_view::scrollWaveforms {delta} {
    variable waveform
    if {$waveform eq "" || ![winfo exists $waveform]} { return }
    set direction [expr {$delta > 0 ? -3 : 3}]
    $waveform yview scroll $direction units
}

proc ::svvs::simulator_view::shortWaveformLabel {label availablePixels} {
    set maxChars [expr {max(5, int($availablePixels / 7.0))}]
    if {[string length $label] <= $maxChars} { return $label }
    return "[string range $label 0 [expr {$maxChars - 4}]]..."
}

proc ::svvs::simulator_view::setStatus {text mode} {
    variable statusLabel
    if {$statusLabel eq "" || ![winfo exists $statusLabel]} { return }
    set colors [dict create idle #51462d ready #244b3a running #1f5265 paused #51462d error #5a3035]
    set foregrounds [dict create idle warning ready success running accentHover paused warning error error]
    set colorName [dict get $foregrounds $mode]
    $statusLabel configure -text [string toupper $text] \
        -background [dict get $colors $mode] -foreground [::svvs::theme::color $colorName]
}

proc ::svvs::simulator_view::refreshSignals {} {
    variable currentModel
    variable process
    if {![info exists ::svvs::canvas_blocks::blocks]} { return }
    set latest [::svvs::simulation_model::diagramModel]
    if {$process ne "" && $currentModel ne "" && $latest ne $currentModel} {
        ::svvs::simulator_view::closeProcess
        ::svvs::simulator_view::setStatus "Diagram changed" idle
    }
    set currentModel $latest
    ::svvs::simulator_view::renderSignalRows
}

proc ::svvs::simulator_view::clearChildren {widget} {
    if {$widget eq "" || ![winfo exists $widget]} { return }
    foreach child [winfo children $widget] { destroy $child }
}

proc ::svvs::simulator_view::renderSignalRows {} {
    variable inputPanel
    variable outputPanel
    variable currentModel
    variable signalVars
    variable valueLabels
    variable signalWidths
    variable history
    variable clockSignal
    variable waveformsEnabled
    array unset signalVars
    array unset valueLabels
    array unset signalWidths
    array set signalVars {}
    array set valueLabels {}
    array set signalWidths {}
    set clockSignal ""
    ::svvs::simulator_view::clearChildren $inputPanel
    ::svvs::simulator_view::clearChildren $outputPanel
    if {$waveformsEnabled && $currentModel ne "" && [dict exists $currentModel traces]} {
        foreach trace [dict get $currentModel traces] {
            set traceName [dict get $trace name]
            if {![info exists history($traceName)]} { set history($traceName) {} }
        }
    }

    set row 0
    foreach signal [dict get $currentModel inputs] {
        set name [dict get $signal name]
        set width [dict get $signal width]
        set signalWidths($name) $width
        set initial 0
        if {[dict exists $signal initialValue]} { set initial [dict get $signal initialValue] }
        set signalVars($name) $initial
        if {$clockSignal eq "" && $width == 1 && [regexp -nocase {(^|__)(clk|clock)} $name]} {
            set clockSignal $name
        }
        ttk::label $inputPanel.name$row -text $name -style Panel.TLabel
        ttk::label $inputPanel.width$row -text "${width}b" -style Muted.Panel.TLabel
        grid $inputPanel.name$row -row $row -column 0 -sticky w -pady 3
        grid $inputPanel.width$row -row $row -column 1 -sticky e -padx 6
        if {$width == 1} {
            ttk::checkbutton $inputPanel.value$row -variable ::svvs::simulator_view::signalVars($name) \
                -command [list ::svvs::simulator_view::applyInput $name]
        } else {
            ttk::entry $inputPanel.value$row -textvariable ::svvs::simulator_view::signalVars($name) -width 10
            bind $inputPanel.value$row <Return> [list ::svvs::simulator_view::applyInput $name]
            bind $inputPanel.value$row <FocusOut> [list ::svvs::simulator_view::applyInput $name]
        }
        grid $inputPanel.value$row -row $row -column 2 -sticky e
        incr row
    }
    grid columnconfigure $inputPanel 0 -weight 1
    if {$row == 0} {
        ttk::label $inputPanel.empty -text "No external inputs" -style Muted.Panel.TLabel
        pack $inputPanel.empty -anchor w
    }

    set row 0
    foreach signal [dict get $currentModel outputs] {
        set name [dict get $signal name]
        set signalWidths($name) [dict get $signal width]
        if {![info exists history($name)]} { set history($name) {} }
        ttk::label $outputPanel.name$row -text $name -style Panel.TLabel
        set valueLabels($name) [label $outputPanel.value$row -text "x" \
            -background [::svvs::theme::color panel] -foreground [::svvs::theme::color accentHover] \
            -font {{Cascadia Mono} 10 bold}]
        grid $outputPanel.name$row -row $row -column 0 -sticky w -pady 4
        grid $outputPanel.value$row -row $row -column 1 -sticky e -padx {10 0}
        incr row
    }
    grid columnconfigure $outputPanel 0 -weight 1
    if {$row == 0} {
        ttk::label $outputPanel.empty -text "No module outputs" -style Muted.Panel.TLabel
        pack $outputPanel.empty -anchor w
    }
    ::svvs::simulator_view::drawWaveforms
}

proc ::svvs::simulator_view::build {} {
    variable currentModel
    variable lastBuildResult
    variable lastBackend
    ::svvs::simulator_view::closeProcess
    ::svvs::simulator_view::setPauseText "Pause"
    set lastBuildResult ""
    set lastBackend ""
    ::svvs::simulator_view::clearWaveformHistory
    ::svvs::simulator_view::setStatus "Building" idle
    update idletasks
    set result [::svvs::simulation_model::prepare]
    set currentModel [dict get $result model]
    ::svvs::simulator_view::renderSignalRows
    if {![dict get $result ok]} {
        set message [dict get $result message]
        if {[dict exists $result missingTool]} {
            set tool [dict get $result missingTool]
            ::svvs::simulator_view::setStatus "[string totitle $tool] missing" error
        } else {
            ::svvs::simulator_view::setStatus "Build error" error
        }
        ::svvs::console::log $message error
        return 0
    }
    set lastBuildResult $result
    if {![::svvs::simulator_view::startBackend $result]} {
        return 0
    }
    ::svvs::console::log "Build concluida e pronta para simulacao." ok
    return 1
}

proc ::svvs::simulator_view::startBackend {result {backend ""}} {
    variable process
    variable currentModel
    variable lastBackend
    set currentModel [dict get $result model]
    if {$backend eq ""} {
        set backend [::svvs::simulation_backends::prepare $result]
    }
    if {![dict get $backend ok]} {
        ::svvs::simulator_view::setStatus "Engine error" error
        ::svvs::console::log "Nenhum motor de simulacao pode iniciar:\n[dict get $backend message]" error
        return 0
    }
    set lastBackend $backend
    set command [linsert [dict get $backend command] 0 |]
    if {[catch {set process [open $command r+]} message]} {
        set process ""
        ::svvs::simulator_view::setStatus "Start error" error
        ::svvs::console::log "Nao foi possivel iniciar o simulador: $message" error
        return 0
    }
    fconfigure $process -blocking 0 -buffering line -encoding utf-8
    fileevent $process readable ::svvs::simulator_view::readBackend
    set engine [dict get $backend engine]
    ::svvs::simulator_view::setStatus "$engine ready" ready
    ::svvs::diagram_simulation::activate $currentModel
    if {[dict get $backend diagnostics] ne ""} {
        ::svvs::console::log "Automatic engine fallback:\n[dict get $backend diagnostics]" warn
    }
    ::svvs::console::log "Motor ativo: $engine." ok
    return 1
}

proc ::svvs::simulator_view::buildAndRun {} {
    if {[::svvs::simulator_view::build]} {
        ::svvs::simulator_view::run
    }
}

proc ::svvs::simulator_view::engineChanged {} {
    variable process
    variable lastBuildResult
    variable lastBackend
    if {$process ne ""} {
        ::svvs::simulator_view::closeProcess
    }
    set lastBackend ""
    set ::svvs::simulation_backends::activeEngine ""
    if {$lastBuildResult eq ""} {
        ::svvs::simulator_view::setStatus "Not built" idle
    } else {
        ::svvs::simulator_view::setStatus "Build available" ready
    }
    ::svvs::console::log "Motor selecionado: $::svvs::simulation_backends::selectedEngine." info
}

proc ::svvs::simulator_view::clearBuildCache {} {
    variable lastBuildResult
    variable lastBackend
    ::svvs::simulator_view::closeProcess
    set lastBuildResult ""
    set lastBackend ""
    set ::svvs::simulation_backends::activeEngine ""
    ::svvs::simulator_view::setPauseText "Pause"
    ::svvs::simulator_view::setStatus "Not built" idle
}

proc ::svvs::simulator_view::clearWaveformHistory {} {
    variable history
    variable simulationStartTime
    variable lastSampleTime
    array unset history
    array set history {}
    set simulationStartTime [clock milliseconds]
    set lastSampleTime $simulationStartTime
    ::svvs::simulator_view::drawWaveforms
}

proc ::svvs::simulator_view::readBackend {} {
    variable process
    if {$process eq ""} { return }
    if {[eof $process]} {
        ::svvs::simulator_view::closeProcess
        ::svvs::simulator_view::setStatus "Stopped" error
        return
    }
    while {[gets $process line] >= 0} {
        set fields [split $line "\t"]
        set kind [lindex $fields 0]
        if {$kind eq "VALUES"} {
            ::svvs::simulator_view::updateValues [lrange $fields 1 end]
        } elseif {$kind eq "READY"} {
            ::svvs::simulator_view::initializeInputs
            ::svvs::simulator_view::initializeFsmWatches
        } elseif {$kind eq "ERROR"} {
            ::svvs::console::log "Simulador: [join [lrange $fields 1 end] { }]" error
            ::svvs::simulator_view::setStatus "Runtime error" error
        }
    }
}

proc ::svvs::simulator_view::initializeFsmWatches {} {
    variable fsmWatches
    array unset fsmWatches
    array set fsmWatches {}
    set diagramModules {}
    if {[info exists ::svvs::canvas_blocks::blocks]} {
        foreach blockId [array names ::svvs::canvas_blocks::blocks] {
            set block $::svvs::canvas_blocks::blocks($blockId)
            if {![dict exists $block module]} { continue }
            set module [dict get $block module]
            if {[dict exists $module name]} {
                lappend diagramModules [dict get $module name]
            }
        }
    }
    set diagramModules [lsort -unique $diagramModules]
    set index 0
    foreach fsm $::svvs::project_tree::fsms {
        if {![dict exists $fsm module] || [dict get $fsm module] ni $diagramModules} {
            continue
        }
        set alias "__fsm_[incr index]"
        set fsmWatches($alias) $fsm
        ::svvs::simulator_view::send WATCH $alias \
            [dict get $fsm module] [dict get $fsm stateVariable]
    }
}

proc ::svvs::simulator_view::initializeInputs {} {
    variable currentModel
    variable signalVars
    if {$currentModel eq ""} { return }
    foreach signal [dict get $currentModel inputs] {
        set name [dict get $signal name]
        set value 0
        if {[dict exists $signal initialValue]} { set value [dict get $signal initialValue] }
        set signalVars($name) $value
        ::svvs::simulator_view::send SET $name $value
    }
}

proc ::svvs::simulator_view::refreshComponentConfiguration {{resetClocks 0}} {
    variable currentModel
    variable clockNext
    set currentModel [::svvs::simulation_model::diagramModel]
    if {$resetClocks} {
        array unset clockNext
        array set clockNext {}
    }
    if {$::svvs::diagram_simulation::active} {
        ::svvs::diagram_simulation::activate $currentModel
    }
    ::svvs::simulator_view::drawWaveforms
}

proc ::svvs::simulator_view::send {args} {
    variable process
    if {$process eq ""} { return 0 }
    if {[catch {puts $process [join $args "\t"]; flush $process}]} {
        ::svvs::simulator_view::closeProcess
        return 0
    }
    return 1
}

proc ::svvs::simulator_view::applyInput {name} {
    variable signalVars
    variable signalWidths
    if {![info exists signalVars($name)]} { return }
    set value [string trim $signalVars($name)]
    if {![string is integer -strict $value] || $value < 0 || $value >= (1 << $signalWidths($name))} {
        ::svvs::console::log "Valor invalido para $name ([set signalWidths($name)] bits)." warn
        return
    }
    ::svvs::simulator_view::send SET $name $value
}

proc ::svvs::simulator_view::setInputValue {name value} {
    variable signalVars
    set signalVars($name) $value
    ::svvs::simulator_view::applyInput $name
}

proc ::svvs::simulator_view::setPauseText {text} {
    variable pauseButton
    if {$pauseButton ne "" && [winfo exists $pauseButton]} {
        $pauseButton configure -text $text
    }
    if {[info exists ::svvs::layout::widgets(toolbar:Pause)]} {
        set widget $::svvs::layout::widgets(toolbar:Pause)
        if {[winfo exists $widget]} { $widget configure -text $text }
    }
}

proc ::svvs::simulator_view::startPreviousBuild {} {
    variable lastBuildResult
    variable lastBackend
    variable currentModel
    if {$lastBuildResult eq ""} {
        ::svvs::simulator_view::setStatus "Build required" idle
        ::svvs::console::log "Nenhuma build disponivel. Use Build and Run primeiro." warn
        return 0
    }
    set latest [::svvs::simulation_model::diagramModel]
    if {$latest ne [dict get $lastBuildResult model]} {
        set currentModel $latest
        ::svvs::simulator_view::setStatus "Build required" idle
        ::svvs::console::log "O diagrama mudou. Use Build and Run para sintetizar novamente." warn
        return 0
    }
    ::svvs::simulator_view::clearWaveformHistory
    return [::svvs::simulator_view::startBackend $lastBuildResult $lastBackend]
}

proc ::svvs::simulator_view::run {} {
    variable process
    variable running
    variable currentModel
    if {$running} { return }
    set latest [::svvs::simulation_model::diagramModel]
    if {$process ne "" && $latest ne $currentModel} {
        ::svvs::simulator_view::closeProcess
        set currentModel $latest
        ::svvs::simulator_view::setStatus "Build required" idle
        ::svvs::console::log "O diagrama mudou. Use Build and Run para sintetizar novamente." warn
        return
    }
    if {$process eq "" && ![::svvs::simulator_view::startPreviousBuild]} { return }
    if {!$::svvs::diagram_simulation::active} {
        ::svvs::diagram_simulation::activate $currentModel
    }
    set running 1
    ::svvs::simulator_view::setPauseText "Pause"
    ::svvs::simulator_view::setStatus "Running" running
    ::svvs::layout::setToolbarActive "Run" 1
    ::svvs::layout::setToolbarActive "Pause" 0
    ::svvs::simulator_view::schedule
}

proc ::svvs::simulator_view::pause {} {
    variable process
    variable running
    variable timer
    if {!$running} {
        if {$process eq ""} { return }
        ::svvs::simulator_view::run
        return
    }
    set running 0
    if {$timer ne ""} { after cancel $timer; set timer "" }
    ::svvs::simulator_view::setPauseText "Continue"
    ::svvs::simulator_view::setStatus "Paused" paused
    ::svvs::layout::setToolbarActive "Run" 0
    ::svvs::layout::setToolbarActive "Pause" 1
}

proc ::svvs::simulator_view::stop {} {
    variable running
    variable timer
    variable cycle
    variable cycleLabel
    variable clockStates
    variable clockNext
    variable lastBuildResult
    set running 0
    if {$timer ne ""} { after cancel $timer; set timer "" }
    ::svvs::simulator_view::closeProcess
    set cycle 0
    if {$cycleLabel ne "" && [winfo exists $cycleLabel]} { $cycleLabel configure -text "Cycle 0" }
    array unset clockStates
    array unset clockNext
    array set clockStates {}
    array set clockNext {}
    ::svvs::simulator_view::setPauseText "Pause"
    if {$lastBuildResult eq ""} {
        ::svvs::simulator_view::setStatus "Stopped" idle
    } else {
        ::svvs::simulator_view::setStatus "Build available" ready
    }
    ::svvs::layout::setToolbarActive "Run" 0
    ::svvs::layout::setToolbarActive "Pause" 0
}

proc ::svvs::simulator_view::step {} {
    variable process
    variable cycle
    variable cycleLabel
    variable clockSignal
    variable currentModel
    set latest [::svvs::simulation_model::diagramModel]
    if {$process ne "" && $latest ne $currentModel} {
        ::svvs::simulator_view::closeProcess
        set currentModel $latest
    }
    if {$process eq "" && ![::svvs::simulator_view::startPreviousBuild]} { return }
    if {!$::svvs::diagram_simulation::active} {
        ::svvs::diagram_simulation::activate $currentModel
    }
    set clocks [dict get $currentModel clocks]
    if {[llength $clocks] > 0} {
        foreach clock $clocks {
            set name [dict get $clock name]
            ::svvs::simulator_view::send SET $name 0
            ::svvs::simulator_view::send SET $name 1
        }
    } elseif {$clockSignal ne ""} {
        ::svvs::simulator_view::send SET $clockSignal 0
        ::svvs::simulator_view::send SET $clockSignal 1
    } else {
        ::svvs::simulator_view::send EVAL
    }
    incr cycle
    $cycleLabel configure -text "Cycle $cycle"
}

proc ::svvs::simulator_view::schedule {} {
    variable running
    variable timer
    variable currentModel
    variable clockStates
    variable clockNext
    variable cycle
    variable cycleLabel
    if {!$running} { return }
    set now [clock milliseconds]
    set clocks [dict get $currentModel clocks]
    set delay 50
    if {[llength $clocks] == 0} {
        ::svvs::simulator_view::send EVAL
    } else {
        foreach clockInfo $clocks {
            set name [dict get $clockInfo name]
            set frequency [dict get $clockInfo frequency]
            set halfPeriod [expr {max(5.0, 500.0 / double($frequency))}]
            set delay [expr {min($delay, max(5, int($halfPeriod / 2.0)))}]
            if {![info exists clockStates($name)]} { set clockStates($name) 0 }
            if {![info exists clockNext($name)]} { set clockNext($name) $now }
            if {$now >= $clockNext($name)} {
                set clockStates($name) [expr {!$clockStates($name)}]
                ::svvs::simulator_view::send SET $name $clockStates($name)
                set clockNext($name) [expr {$now + $halfPeriod}]
                if {$clockStates($name)} {
                    incr cycle
                    $cycleLabel configure -text "Cycle $cycle"
                }
            }
        }
    }
    set timer [after $delay ::svvs::simulator_view::schedule]
}

proc ::svvs::simulator_view::updateValues {pairs} {
    variable valueLabels
    variable signalVars
    variable currentModel
    variable simulationStartTime
    variable lastSampleTime
    variable fsmWatches
    variable waveformsEnabled
    set sampleTime [clock milliseconds]
    if {$simulationStartTime == 0} { set simulationStartTime $sampleTime }
    set lastSampleTime $sampleTime
    variable history
    variable currentModel
    set traceNames {}
    set traceInfo {}
    if {$currentModel ne "" && [dict exists $currentModel traces]} {
        foreach trace [dict get $currentModel traces] {
            dict set traceNames [dict get $trace name] 1
            if {![dict exists $traceInfo [dict get $trace name]]} {
                dict set traceInfo [dict get $trace name] $trace
            }
        }
    }
    foreach pair $pairs {
        set equals [string first = $pair]
        if {$equals < 1} { continue }
        set name [string range $pair 0 [expr {$equals - 1}]]
        set value [string range $pair [expr {$equals + 1}] end]
        if {[info exists fsmWatches($name)]} {
            ::svvs::fsm_viewer::setRuntimeValue $fsmWatches($name) $value
            continue
        }
        if {[info exists valueLabels($name)] && [winfo exists $valueLabels($name)]} {
            set display $value
            if {[dict exists $traceInfo $name]} {
                set trace [dict get $traceInfo $name]
                set traceWidth [expr {[dict exists $trace width] ? [dict get $trace width] : 1}]
                set traceBase [expr {[dict exists $trace base] ? [dict get $trace base] : "dec"}]
                set valueMap [expr {[dict exists $trace valueMap] ? [dict get $trace valueMap] : {}}]
                set display [::svvs::simulation_components::formatMappedValue \
                    $value $traceWidth $traceBase $valueMap]
            }
            $valueLabels($name) configure -text $display
        }
        if {$waveformsEnabled && [dict exists $traceNames $name]} {
            if {![info exists history($name)]} { set history($name) {} }
            set appendSample 1
            if {[llength $history($name)] > 0 &&
                [lindex [lindex $history($name) end] 1] eq $value} {
                set appendSample 0
            }
            if {$appendSample} {
                lappend history($name) [list $sampleTime $value]
                set history($name) [lrange $history($name) end-499 end]
            }
        }
        if {[info exists signalVars($name)]} { set signalVars($name) $value }
    }
    ::svvs::diagram_simulation::updateValues $pairs
    if {$waveformsEnabled} {
        ::svvs::simulator_view::drawWaveforms
    }
}

proc ::svvs::simulator_view::drawWaveforms {} {
    variable waveform
    variable currentModel
    variable history
    variable simulationStartTime
    variable lastSampleTime
    variable waveformWindowMs
    variable waveformsEnabled
    if {$waveform eq "" || ![winfo exists $waveform]} { return }
    $waveform delete all
    set width [winfo width $waveform]
    set height [winfo height $waveform]
    if {$width < 20} { set width 700 }
    if {$height < 20} { set height 150 }
    $waveform create text 14 16 -text "LIVE WAVEFORMS" -anchor w \
        -fill [::svvs::theme::color muted] -font {{Segoe UI} 8 bold}
    if {!$waveformsEnabled} {
        $waveform configure -scrollregion [list 0 0 $width $height]
        $waveform create text 22 55 \
            -text "Waveform generation disabled." \
            -anchor w -fill [::svvs::theme::color muted]
        return
    }
    if {$currentModel eq ""} { return }
    set outputs [dict get $currentModel traces]
    if {[llength $outputs] == 0} {
        $waveform configure -scrollregion [list 0 0 $width $height]
        $waveform create text 22 55 -text "Add signal blocks to select waveforms." -anchor w \
            -fill [::svvs::theme::color muted]
        return
    }
    set x0 [expr {max(92, min(170, int($width * 0.27)))}]
    set x1 [expr {$width - 18}]
    if {$x1 <= $x0 + 40} { set x0 72 }
    set rowHeight 48
    set contentHeight [expr {max($height, 42 + ([llength $outputs] * $rowHeight))}]
    $waveform configure -scrollregion [list 0 0 $width $contentHeight]
    set endTime [expr {$lastSampleTime > 0 ? $lastSampleTime : [clock milliseconds]}]
    set startTime [expr {max($simulationStartTime, $endTime - $waveformWindowMs)}]
    if {$endTime <= $startTime} { set endTime [expr {$startTime + 1}] }
    $waveform create line $x0 29 $x1 29 -fill [::svvs::theme::color border]
    for {set tick 0} {$tick <= 4} {incr tick} {
        set fraction [expr {$tick / 4.0}]
        set x [expr {$x0 + (($x1 - $x0) * $fraction)}]
        set tickTime [expr {$startTime + (($endTime - $startTime) * $fraction)}]
        set label [format "%.2fs" [expr {($tickTime - $simulationStartTime) / 1000.0}]]
        $waveform create line $x 26 $x [expr {$contentHeight - 8}] -fill #262b31
        $waveform create text $x 17 -text $label -anchor n -fill [::svvs::theme::color muted] \
            -font {{Cascadia Mono} 7}
    }
    set y 48
    foreach signal $outputs {
        set name [dict get $signal name]
        set label $name
        if {[dict exists $signal label]} { set label [dict get $signal label] }
        set label [::svvs::simulator_view::shortWaveformLabel $label [expr {$x0 - 34}]]
        $waveform create text 14 $y -text $label -anchor w -fill [::svvs::theme::color text]
        $waveform create line $x0 [expr {$y + 12}] $x1 [expr {$y + 12}] -fill #30363d
        if {[info exists history($name)] && [llength $history($name)] > 0} {
            set signalWidth 1
            if {[dict exists $signal width]} { set signalWidth [dict get $signal width] }
            set samples [::svvs::simulator_view::visibleSamples $history($name) $startTime $endTime]
            if {$signalWidth == 1} {
                ::svvs::simulator_view::drawDigitalWave $samples $x0 $x1 $y $startTime $endTime
                if {[dict exists $signal valueMap] && [dict size [dict get $signal valueMap]] > 0} {
                    ::svvs::simulator_view::drawMappedWaveLabels $samples $x0 $x1 $y \
                        $startTime $endTime [dict get $signal valueMap]
                }
            } else {
                set base dec
                if {[dict exists $signal base]} { set base [dict get $signal base] }
                set valueMap [expr {[dict exists $signal valueMap] ? [dict get $signal valueMap] : {}}]
                ::svvs::simulator_view::drawBusWave \
                    $samples $x0 $x1 $y $startTime $endTime $signalWidth $base $valueMap
            }
        }
        incr y $rowHeight
    }
}

proc ::svvs::simulator_view::visibleSamples {samples startTime endTime} {
    set previous ""
    set visible {}
    foreach sample $samples {
        lassign $sample timestamp value
        if {$timestamp < $startTime} {
            set previous $sample
        } elseif {$timestamp <= $endTime} {
            lappend visible $sample
        }
    }
    if {$previous ne ""} {
        set visible [linsert $visible 0 [list $startTime [lindex $previous 1]]]
    } elseif {[llength $visible] > 0 && [lindex [lindex $visible 0] 0] > $startTime} {
        set visible [linsert $visible 0 [list $startTime [lindex [lindex $visible 0] 1]]]
    }
    return $visible
}

proc ::svvs::simulator_view::timeToX {timestamp startTime endTime x0 x1} {
    return [expr {$x0 + (($timestamp - $startTime) * double($x1 - $x0) / ($endTime - $startTime))}]
}

proc ::svvs::simulator_view::drawDigitalWave {samples x0 x1 y startTime endTime} {
    variable waveform
    if {[llength $samples] == 0} { return }
    set highY [expr {$y - 5}]
    set lowY [expr {$y + 18}]
    set middleY [expr {$y + 7}]
    set first [lindex $samples 0]
    set previousValue [lindex $first 1]
    set previousY [expr {$previousValue eq "1" ? $highY : ($previousValue eq "0" ? $lowY : $middleY)}]
    set points [list $x0 $previousY]
    foreach sample [lrange $samples 1 end] {
        lassign $sample timestamp value
        set x [::svvs::simulator_view::timeToX $timestamp $startTime $endTime $x0 $x1]
        set nextY [expr {$value eq "1" ? $highY : ($value eq "0" ? $lowY : $middleY)}]
        lappend points $x $previousY $x $nextY
        set previousY $nextY
        set previousValue $value
    }
    lappend points $x1 $previousY
    $waveform create line $points -fill [::svvs::theme::color accentHover] -width 2
}

proc ::svvs::simulator_view::drawMappedWaveLabels {samples x0 x1 y startTime endTime valueMap} {
    variable waveform
    set count [llength $samples]
    for {set index 0} {$index < $count} {incr index} {
        lassign [lindex $samples $index] timestamp value
        if {![string is integer -strict $value]} { continue }
        set key [expr {int($value)}]
        if {![dict exists $valueMap $key]} { continue }
        set nextTime $endTime
        if {$index + 1 < $count} {
            set nextTime [lindex [lindex $samples [expr {$index + 1}]] 0]
        }
        set sx [::svvs::simulator_view::timeToX $timestamp $startTime $endTime $x0 $x1]
        set ex [::svvs::simulator_view::timeToX $nextTime $startTime $endTime $x0 $x1]
        set display [dict get $valueMap $key]
        if {$ex - $sx >= max(26, [string length $display] * 6)} {
            $waveform create text [expr {($sx + $ex) / 2.0}] [expr {$y + 7}] -text $display \
                -fill [::svvs::theme::color text] -font {{Segoe UI} 7 bold}
        }
    }
}

proc ::svvs::simulator_view::drawBusWave {samples x0 x1 y startTime endTime width base {valueMap {}}} {
    variable waveform
    if {[llength $samples] == 0} { return }
    set topY [expr {$y - 4}]
    set bottomY [expr {$y + 18}]
    set middleY [expr {($topY + $bottomY) / 2.0}]
    set count [llength $samples]
    for {set index 0} {$index < $count} {incr index} {
        lassign [lindex $samples $index] timestamp value
        set nextTime $endTime
        if {$index + 1 < $count} { set nextTime [lindex [lindex $samples [expr {$index + 1}]] 0] }
        set sx [::svvs::simulator_view::timeToX $timestamp $startTime $endTime $x0 $x1]
        set ex [::svvs::simulator_view::timeToX $nextTime $startTime $endTime $x0 $x1]
        set slant [expr {min(6.0, max(0.0, ($ex - $sx) / 3.0))}]
        set left [expr {$index == 0 ? 0.0 : $slant}]
        set right [expr {$index + 1 == $count ? 0.0 : $slant}]
        set outline [expr {$value in {x z} ? [::svvs::theme::color error] : [::svvs::theme::color accentHover]}]
        set fill [expr {$value in {x z} ? "#3a2428" : "#202a30"}]
        set points [list \
            [expr {$sx + $left}] $topY [expr {$ex - $right}] $topY \
            $ex $middleY [expr {$ex - $right}] $bottomY \
            [expr {$sx + $left}] $bottomY $sx $middleY]
        $waveform create polygon $points -fill $fill -outline $outline -width 1
        set display [::svvs::simulation_components::formatMappedValue \
            $value $width $base $valueMap]
        set available [expr {$ex - $sx - 8}]
        if {$available >= max(20, [string length $display] * 6)} {
            $waveform create text [expr {($sx + $ex) / 2.0}] $middleY -text $display \
                -fill $outline -font {{Cascadia Mono} 7} -anchor center
        }
    }
}

proc ::svvs::simulator_view::closeProcess {} {
    variable process
    variable running
    variable timer
    set running 0
    if {$timer ne ""} { after cancel $timer; set timer "" }
    if {$process ne ""} {
        catch {fileevent $process readable {}}
        catch {puts $process QUIT; flush $process}
        catch {close $process}
        set process ""
    }
    ::svvs::diagram_simulation::deactivate
}
