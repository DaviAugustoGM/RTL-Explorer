namespace eval ::svvs::pdf_export {
    variable activeStyle original
    variable dialogKind blocks
    variable dialogStyle light
}

proc ::svvs::pdf_export::itemOption {canvas item option {default ""}} {
    if {[catch {$canvas itemcget $item $option} value]} { return $default }
    return $value
}

proc ::svvs::pdf_export::includeItem {canvas item} {
    if {[::svvs::pdf_export::itemOption $canvas $item -state normal] eq "hidden"} { return 0 }
    foreach tag [$canvas gettags $item] {
        if {[string match "*hit*" $tag] || [string match "*handle*" $tag] ||
            $tag in {simulation-hud}} { return 0 }
    }
    return 1
}

proc ::svvs::pdf_export::canvasBounds {canvas} {
    set bounds ""
    foreach item [$canvas find all] {
        if {![::svvs::pdf_export::includeItem $canvas $item]} { continue }
        set box [$canvas bbox $item]
        if {[llength $box] != 4} { continue }
        if {$bounds eq ""} {
            set bounds $box
        } else {
            lassign $bounds x1 y1 x2 y2
            lassign $box bx1 by1 bx2 by2
            set bounds [list [expr {min($x1, $bx1)}] [expr {min($y1, $by1)}] \
                [expr {max($x2, $bx2)}] [expr {max($y2, $by2)}]]
        }
    }
    return $bounds
}

proc ::svvs::pdf_export::rgb {canvas color} {
    variable activeStyle
    if {$color eq ""} { return "" }
    if {[catch {winfo rgb $canvas $color} values]} { return "" }
    lassign $values r g b
    if {$activeStyle eq "light"} {
        set source [format "#%02x%02x%02x" \
            [expr {round($r / 257.0)}] [expr {round($g / 257.0)}] [expr {round($b / 257.0)}]]
        set palette [dict create \
            #181a1e #ffffff #22252a #ffffff #1d2024 #f8fafc \
            #292c31 #e2e8f0 #15171a #ffffff #d9dee7 #111827 \
            #94a0ad #475569 #39a6d3 #0369a1 #52b9e2 #0284c7 \
            #2b2f35 #f8fafc #343941 #e2e8f0 #294b5f #dbeafe \
            #383d45 #94a3b8 #e06c75 #b91c1c #e5c07b #a16207 \
            #7fb069 #15803d #58b8c7 #0891b2 #e6a07b #c2410c \
            #969fa9 #475569 #ffffff #111827 #262b31 #e2e8f0 \
            #30363d #cbd5e1 #202a30 #f1f5f9 #3a2428 #fee2e2]
        if {[dict exists $palette $source]} {
            set color [dict get $palette $source]
            set values [winfo rgb $canvas $color]
            lassign $values r g b
        }
    }
    return [format "%.4f %.4f %.4f" \
        [expr {$r / 65535.0}] [expr {$g / 65535.0}] [expr {$b / 65535.0}]]
}

proc ::svvs::pdf_export::px {geometry x} {
    return [expr {[dict get $geometry marginX] + (($x - [dict get $geometry minX]) * [dict get $geometry scale])}]
}

proc ::svvs::pdf_export::py {geometry y} {
    return [expr {[dict get $geometry marginY] + (([dict get $geometry maxY] - $y) * [dict get $geometry scale])}]
}

proc ::svvs::pdf_export::paintOperator {fill stroke} {
    if {$fill ne "" && $stroke ne ""} { return B }
    if {$fill ne ""} { return f }
    if {$stroke ne ""} { return S }
    return n
}

proc ::svvs::pdf_export::paintSetup {canvas fill outline width scale} {
    set result "q\n"
    set fillRgb [::svvs::pdf_export::rgb $canvas $fill]
    set strokeRgb [::svvs::pdf_export::rgb $canvas $outline]
    if {$fillRgb ne ""} { append result "$fillRgb rg\n" }
    if {$strokeRgb ne ""} { append result "$strokeRgb RG\n" }
    append result [format "%.3f w\n" [expr {max(0.5, double($width) * $scale)}]]
    return [list $result $fillRgb $strokeRgb]
}

proc ::svvs::pdf_export::rectangleCommands {canvas item geometry} {
    lassign [$canvas coords $item] x1 y1 x2 y2
    set fill [::svvs::pdf_export::itemOption $canvas $item -fill]
    set outline [::svvs::pdf_export::itemOption $canvas $item -outline]
    set width [::svvs::pdf_export::itemOption $canvas $item -width 1]
    lassign [::svvs::pdf_export::paintSetup $canvas $fill $outline $width \
        [dict get $geometry scale]] commands fillRgb strokeRgb
    set x [::svvs::pdf_export::px $geometry $x1]
    set y [::svvs::pdf_export::py $geometry $y2]
    set w [expr {($x2 - $x1) * [dict get $geometry scale]}]
    set h [expr {($y2 - $y1) * [dict get $geometry scale]}]
    append commands [format "%.3f %.3f %.3f %.3f re %s\nQ\n" \
        $x $y $w $h [::svvs::pdf_export::paintOperator $fillRgb $strokeRgb]]
    return $commands
}

proc ::svvs::pdf_export::ovalCommands {canvas item geometry} {
    lassign [$canvas coords $item] x1 y1 x2 y2
    set left [::svvs::pdf_export::px $geometry $x1]
    set right [::svvs::pdf_export::px $geometry $x2]
    set bottom [::svvs::pdf_export::py $geometry $y2]
    set top [::svvs::pdf_export::py $geometry $y1]
    set cx [expr {($left + $right) / 2.0}]
    set cy [expr {($bottom + $top) / 2.0}]
    set rx [expr {($right - $left) / 2.0}]
    set ry [expr {($top - $bottom) / 2.0}]
    set k 0.5522847498
    set fill [::svvs::pdf_export::itemOption $canvas $item -fill]
    set outline [::svvs::pdf_export::itemOption $canvas $item -outline]
    set width [::svvs::pdf_export::itemOption $canvas $item -width 1]
    lassign [::svvs::pdf_export::paintSetup $canvas $fill $outline $width \
        [dict get $geometry scale]] commands fillRgb strokeRgb
    append commands [format "%.3f %.3f m\n" [expr {$cx + $rx}] $cy]
    append commands [format "%.3f %.3f %.3f %.3f %.3f %.3f c\n" \
        [expr {$cx + $rx}] [expr {$cy + $k*$ry}] [expr {$cx + $k*$rx}] [expr {$cy + $ry}] $cx [expr {$cy + $ry}]]
    append commands [format "%.3f %.3f %.3f %.3f %.3f %.3f c\n" \
        [expr {$cx - $k*$rx}] [expr {$cy + $ry}] [expr {$cx - $rx}] [expr {$cy + $k*$ry}] [expr {$cx - $rx}] $cy]
    append commands [format "%.3f %.3f %.3f %.3f %.3f %.3f c\n" \
        [expr {$cx - $rx}] [expr {$cy - $k*$ry}] [expr {$cx - $k*$rx}] [expr {$cy - $ry}] $cx [expr {$cy - $ry}]]
    append commands [format "%.3f %.3f %.3f %.3f %.3f %.3f c\n" \
        [expr {$cx + $k*$rx}] [expr {$cy - $ry}] [expr {$cx + $rx}] [expr {$cy - $k*$ry}] [expr {$cx + $rx}] $cy]
    append commands "h [::svvs::pdf_export::paintOperator $fillRgb $strokeRgb]\nQ\n"
    return $commands
}

proc ::svvs::pdf_export::polygonCommands {canvas item geometry} {
    set coords [$canvas coords $item]
    if {[llength $coords] < 4} { return "" }
    set fill [::svvs::pdf_export::itemOption $canvas $item -fill]
    set outline [::svvs::pdf_export::itemOption $canvas $item -outline]
    set width [::svvs::pdf_export::itemOption $canvas $item -width 1]
    lassign [::svvs::pdf_export::paintSetup $canvas $fill $outline $width \
        [dict get $geometry scale]] commands fillRgb strokeRgb
    append commands [format "%.3f %.3f m\n" \
        [::svvs::pdf_export::px $geometry [lindex $coords 0]] \
        [::svvs::pdf_export::py $geometry [lindex $coords 1]]]
    foreach {x y} [lrange $coords 2 end] {
        append commands [format "%.3f %.3f l\n" \
            [::svvs::pdf_export::px $geometry $x] [::svvs::pdf_export::py $geometry $y]]
    }
    append commands "h [::svvs::pdf_export::paintOperator $fillRgb $strokeRgb]\nQ\n"
    return $commands
}

proc ::svvs::pdf_export::arrowCommands {canvas geometry color x1 y1 x2 y2} {
    set dx [expr {$x2 - $x1}]
    set dy [expr {$y2 - $y1}]
    set length [expr {sqrt(($dx*$dx) + ($dy*$dy))}]
    if {$length < 0.01} { return "" }
    set ux [expr {$dx / $length}]
    set uy [expr {$dy / $length}]
    set size [expr {max(5.0, 9.0 * [dict get $geometry scale])}]
    set half [expr {$size * 0.45}]
    set bx [expr {$x2 - ($ux * $size)}]
    set by [expr {$y2 - ($uy * $size)}]
    set p1x [expr {$bx - ($uy * $half)}]
    set p1y [expr {$by + ($ux * $half)}]
    set p2x [expr {$bx + ($uy * $half)}]
    set p2y [expr {$by - ($ux * $half)}]
    set rgb [::svvs::pdf_export::rgb $canvas $color]
    if {$rgb eq ""} { return "" }
    return [format "q\n%s rg\n%.3f %.3f m %.3f %.3f l %.3f %.3f l h f\nQ\n" \
        $rgb $x2 $y2 $p1x $p1y $p2x $p2y]
}

proc ::svvs::pdf_export::lineCommands {canvas item geometry} {
    set coords [$canvas coords $item]
    if {[llength $coords] < 4} { return "" }
    set color [::svvs::pdf_export::itemOption $canvas $item -fill]
    set rgb [::svvs::pdf_export::rgb $canvas $color]
    if {$rgb eq ""} { return "" }
    set width [::svvs::pdf_export::itemOption $canvas $item -width 1]
    set scale [dict get $geometry scale]
    set points {}
    foreach {x y} $coords {
        lappend points [::svvs::pdf_export::px $geometry $x] [::svvs::pdf_export::py $geometry $y]
    }
    set commands [format "q\n%s RG\n%.3f w\n1 J 1 j\n" $rgb [expr {max(0.5, $width*$scale)}]]
    append commands [format "%.3f %.3f m\n" [lindex $points 0] [lindex $points 1]]
    foreach {x y} [lrange $points 2 end] { append commands [format "%.3f %.3f l\n" $x $y] }
    append commands "S\nQ\n"
    set arrow [::svvs::pdf_export::itemOption $canvas $item -arrow none]
    if {$arrow in {last both}} {
        append commands [::svvs::pdf_export::arrowCommands $canvas $geometry $color \
            [lindex $points end-3] [lindex $points end-2] [lindex $points end-1] [lindex $points end]]
    }
    if {$arrow in {first both}} {
        append commands [::svvs::pdf_export::arrowCommands $canvas $geometry $color \
            [lindex $points 2] [lindex $points 3] [lindex $points 0] [lindex $points 1]]
    }
    return $commands
}

proc ::svvs::pdf_export::safeText {text} {
    set text [regsub -all {[^\x20-\x7e\n]} $text {?}]
    return [string map {\\ \\\\ ( \\( ) \\)} $text]
}

proc ::svvs::pdf_export::textCommands {canvas item geometry} {
    set text [::svvs::pdf_export::itemOption $canvas $item -text]
    if {$text eq ""} { return "" }
    set box [$canvas bbox $item]
    if {[llength $box] != 4} { return "" }
    set color [::svvs::pdf_export::rgb $canvas \
        [::svvs::pdf_export::itemOption $canvas $item -fill black]]
    set fontSpec [::svvs::pdf_export::itemOption $canvas $item -font TkDefaultFont]
    set family [font actual $fontSpec -family]
    set weight [font actual $fontSpec -weight]
    set sourceSize [font actual $fontSpec -size]
    if {$sourceSize < 0} { set sourceSize [expr {abs($sourceSize) * 0.75}] }
    set size [expr {max(4.0, abs($sourceSize) * [dict get $geometry scale])}]
    set mono [regexp -nocase {consolas|cascadia|courier|mono} $family]
    if {$mono} {
        set fontName [expr {$weight eq "bold" ? "F4" : "F3"}]
    } else {
        set fontName [expr {$weight eq "bold" ? "F2" : "F1"}]
    }
    set x [::svvs::pdf_export::px $geometry [lindex $box 0]]
    set top [::svvs::pdf_export::py $geometry [lindex $box 1]]
    set leading [expr {$size * 1.18}]
    set commands "q\n$color rg\nBT\n/$fontName [format %.3f $size] Tf\n"
    set lineIndex 0
    foreach line [split $text "\n"] {
        set y [expr {$top - ($size * 0.88) - ($lineIndex * $leading)}]
        append commands [format "1 0 0 1 %.3f %.3f Tm (%s) Tj\n" \
            $x $y [::svvs::pdf_export::safeText $line]]
        incr lineIndex
    }
    append commands "ET\nQ\n"
    return $commands
}

proc ::svvs::pdf_export::canvasCommands {canvas geometry pageWidth pageHeight} {
    set background [::svvs::pdf_export::rgb $canvas [$canvas cget -background]]
    set commands "$background rg\n0 0 $pageWidth $pageHeight re f\n"
    foreach item [$canvas find all] {
        if {![::svvs::pdf_export::includeItem $canvas $item]} { continue }
        switch -- [$canvas type $item] {
            rectangle { append commands [::svvs::pdf_export::rectangleCommands $canvas $item $geometry] }
            oval { append commands [::svvs::pdf_export::ovalCommands $canvas $item $geometry] }
            polygon { append commands [::svvs::pdf_export::polygonCommands $canvas $item $geometry] }
            line { append commands [::svvs::pdf_export::lineCommands $canvas $item $geometry] }
            text { append commands [::svvs::pdf_export::textCommands $canvas $item $geometry] }
        }
    }
    return $commands
}

proc ::svvs::pdf_export::pdfDocument {content pageWidth pageHeight title} {
    set title [::svvs::pdf_export::safeText $title]
    set objects [list \
        {<< /Type /Catalog /Pages 2 0 R >>} \
        {<< /Type /Pages /Kids [3 0 R] /Count 1 >>} \
        "<< /Type /Page /Parent 2 0 R /MediaBox \[0 0 $pageWidth $pageHeight\] /Resources << /Font << /F1 4 0 R /F2 5 0 R /F3 6 0 R /F4 7 0 R >> >> /Contents 8 0 R >>" \
        {<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>} \
        {<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>} \
        {<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>} \
        {<< /Type /Font /Subtype /Type1 /BaseFont /Courier-Bold >>} \
        "<< /Length [string length $content] >>\nstream\n$content\nendstream" \
        "<< /Title ($title) /Creator (RTL Explorer) >>"]
    set pdf "%PDF-1.4\n% RTL Explorer\n"
    set offsets [list 0]
    set number 0
    foreach object $objects {
        incr number
        lappend offsets [string length $pdf]
        append pdf "$number 0 obj\n$object\nendobj\n"
    }
    set xref [string length $pdf]
    append pdf "xref\n0 [expr {[llength $objects] + 1}]\n"
    append pdf "0000000000 65535 f \n"
    foreach offset [lrange $offsets 1 end] {
        append pdf [format "%010d 00000 n \n" $offset]
    }
    append pdf "trailer\n<< /Size [expr {[llength $objects] + 1}] /Root 1 0 R /Info 9 0 R >>\n"
    append pdf "startxref\n$xref\n%%EOF\n"
    return $pdf
}

proc ::svvs::pdf_export::exportCanvas {canvas path title {style original}} {
    variable activeStyle
    set bounds [::svvs::pdf_export::canvasBounds $canvas]
    if {[llength $bounds] != 4} { error "The diagram is empty." }
    lassign $bounds minX minY maxX maxY
    set padding 18.0
    set minX [expr {$minX - $padding}]
    set minY [expr {$minY - $padding}]
    set maxX [expr {$maxX + $padding}]
    set maxY [expr {$maxY + $padding}]
    set contentWidth [expr {max(1.0, $maxX - $minX)}]
    set contentHeight [expr {max(1.0, $maxY - $minY)}]
    if {$contentWidth >= $contentHeight} {
        set pageWidth 842
        set pageHeight 595
    } else {
        set pageWidth 595
        set pageHeight 842
    }
    set pageMargin 34.0
    set scale [expr {min(($pageWidth - 2*$pageMargin) / $contentWidth,
        ($pageHeight - 2*$pageMargin) / $contentHeight)}]
    set drawnWidth [expr {$contentWidth * $scale}]
    set drawnHeight [expr {$contentHeight * $scale}]
    set geometry [dict create minX $minX maxY $maxY scale $scale \
        marginX [expr {($pageWidth - $drawnWidth) / 2.0}] \
        marginY [expr {($pageHeight - $drawnHeight) / 2.0}]]
    set previousStyle $activeStyle
    set activeStyle $style
    set content [::svvs::pdf_export::canvasCommands $canvas $geometry $pageWidth $pageHeight]
    set activeStyle $previousStyle
    set pdf [::svvs::pdf_export::pdfDocument $content $pageWidth $pageHeight $title]
    set fh [open $path wb]
    fconfigure $fh -translation binary -encoding iso8859-1
    puts -nonewline $fh $pdf
    close $fh
}

proc ::svvs::pdf_export::suggestedName {kind} {
    set project [expr {[info exists ::svvs::project_tree::projectName] ?
        $::svvs::project_tree::projectName : "rtl_diagram"}]
    set project [regsub -all {[^A-Za-z0-9_.-]} $project {_}]
    if {$kind eq "fsm" && $::svvs::fsm_viewer::currentFSM ne ""} {
        return "[dict get $::svvs::fsm_viewer::currentFSM module]_fsm.pdf"
    }
    return "${project}_blocks.pdf"
}

proc ::svvs::pdf_export::exportDialog {kind} {
    if {$kind eq "fsm"} {
        if {$::svvs::fsm_viewer::currentFSM eq ""} {
            ::svvs::console::log "Nenhuma maquina de estados esta aberta para exportar." warn
            return
        }
    } else {
        if {[array size ::svvs::canvas_blocks::blocks] == 0} {
            ::svvs::console::log "O diagrama de blocos esta vazio." warn
            return
        }
    }
    variable dialogKind
    variable dialogStyle
    set dialogKind $kind
    set dialogStyle light
    catch {destroy .pdfExportOptions}
    toplevel .pdfExportOptions
    wm title .pdfExportOptions "Export PDF"
    wm transient .pdfExportOptions .
    wm resizable .pdfExportOptions 0 0
    ttk::label .pdfExportOptions.title -text "Document appearance"
    ttk::radiobutton .pdfExportOptions.light -text "White document" \
        -variable ::svvs::pdf_export::dialogStyle -value light
    ttk::radiobutton .pdfExportOptions.original -text "Original dark colors" \
        -variable ::svvs::pdf_export::dialogStyle -value original
    ttk::button .pdfExportOptions.cancel -text "Cancel" -command {destroy .pdfExportOptions}
    ttk::button .pdfExportOptions.export -text "Export..." \
        -command ::svvs::pdf_export::commitExportDialog
    grid .pdfExportOptions.title -row 0 -column 0 -columnspan 2 -sticky w -padx 16 -pady {16 9}
    grid .pdfExportOptions.light -row 1 -column 0 -columnspan 2 -sticky w -padx 16 -pady 3
    grid .pdfExportOptions.original -row 2 -column 0 -columnspan 2 -sticky w -padx 16 -pady 3
    grid .pdfExportOptions.cancel -row 3 -column 0 -sticky e -padx 6 -pady 16
    grid .pdfExportOptions.export -row 3 -column 1 -sticky w -padx 6 -pady 16
    focus .pdfExportOptions.export
}

proc ::svvs::pdf_export::commitExportDialog {} {
    variable dialogKind
    variable dialogStyle
    set kind $dialogKind
    set style $dialogStyle
    destroy .pdfExportOptions
    set path [tk_getSaveFile -title "Export PDF" \
        -initialfile [::svvs::pdf_export::suggestedName $kind] \
        -defaultextension .pdf \
        -filetypes {{"PDF document" {.pdf}} {"All files" {*}}}]
    if {$path eq ""} { return }
    if {$kind eq "fsm"} {
        set canvas $::svvs::fsm_viewer::canvas
        set title "[dict get $::svvs::fsm_viewer::currentFSM module] FSM"
    } else {
        set canvas $::svvs::canvas_blocks::canvas
        set title "$::svvs::project_tree::projectName block diagram"
    }
    if {[catch {::svvs::pdf_export::exportCanvas $canvas $path $title $style} message]} {
        ::svvs::console::log "Falha ao gerar PDF: $message" error
        return
    }
    ::svvs::console::log "PDF gerado: $path" ok
}

proc ::svvs::pdf_export::exportCurrent {} {
    if {[info exists ::svvs::layout::widgets(notebook)] &&
        [$::svvs::layout::widgets(notebook) select] eq $::svvs::layout::widgets(fsmTab)} {
        ::svvs::pdf_export::exportDialog fsm
    } else {
        ::svvs::pdf_export::exportDialog blocks
    }
}
