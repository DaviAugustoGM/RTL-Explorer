set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
proc bgerror {message} { puts stderr "UI ERROR: $message\n$::errorInfo"; exit 1 }
source [file join $root src main.tcl]

proc assertPdf {path} {
    if {![file exists $path] || [file size $path] < 800} { error "PDF was not generated: $path" }
    set fh [open $path rb]
    fconfigure $fh -translation binary -encoding iso8859-1
    set data [read $fh]
    close $fh
    if {![string match {%PDF-1.4*} $data] ||
        [string first "xref" $data] < 0 || [string first "%%EOF" $data] < 0} {
        error "invalid PDF structure: $path"
    }
}

proc runPdfExportTest {} {
    set module [dict create name demo instance u_demo ports [list \
        [dict create name clk direction input width 1] \
        [dict create name data direction input width 8] \
        [dict create name valid direction output width 1]]]
    ::svvs::canvas_blocks::drawBlock $module 120 100
    set blockPdf [file join $::root tests generated_blocks.pdf]
    set fsmPdf [file join $::root tests generated_fsm.pdf]
    ::svvs::pdf_export::exportCanvas $::svvs::canvas_blocks::canvas $blockPdf "Block diagram" light
    assertPdf $blockPdf
    set fh [open $blockPdf rb]
    fconfigure $fh -translation binary -encoding iso8859-1
    set lightData [read $fh]
    close $fh
    if {[string first "1.0000 1.0000 1.0000 rg" $lightData] < 0 ||
        [string first "0.0667 0.0941 0.1529 rg" $lightData] < 0} {
        error "white-document palette was not written to the PDF"
    }

    set fsm [dict create name demo_state module demo stateVariable state \
        states {IDLE LOAD WAIT DONE} transitions [list \
            [dict create from IDLE to LOAD condition start] \
            [dict create from LOAD to WAIT condition ready] \
            [dict create from WAIT to DONE condition complete] \
            [dict create from DONE to IDLE condition default]] \
        initialState IDLE resetCondition rst]
    ::svvs::fsm_viewer::showFSM $fsm
    update idletasks
    ::svvs::fsm_viewer::redraw
    ::svvs::pdf_export::exportCanvas $::svvs::fsm_viewer::canvas $fsmPdf "State machine"
    assertPdf $fsmPdf

    file delete $blockPdf $fsmPdf
    puts "PDF export UI test: ok"
    destroy .
    set ::pdfTestDone 1
}

after 300 runPdfExportTest
vwait ::pdfTestDone
