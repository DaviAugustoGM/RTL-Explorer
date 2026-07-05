namespace eval ::svvs::documentation {}

proc ::svvs::documentation::create {parent} {
    text $parent.text \
        -wrap word \
        -background [::svvs::theme::color bg] \
        -foreground [::svvs::theme::color text] \
        -insertbackground [::svvs::theme::color text] \
        -selectbackground [::svvs::theme::color selected] \
        -borderwidth 0 \
        -highlightthickness 0
    pack $parent.text -fill both -expand 1

    $parent.text insert end "Documentacao automatica\n\n"
    $parent.text insert end "Esta area esta preparada para listar modulos, portas, parametros, FSMs, instancias e conexoes detectadas a partir dos arquivos SystemVerilog.\n\n"
    $parent.text insert end "Modulos de exemplo:\n- uart_rx\n- fifo_sync\n- uart_tx\n"
    $parent.text configure -state disabled
}
