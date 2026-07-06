namespace eval ::svvs::simulation_backends {
    variable selectedEngine "Automatic"
    variable activeEngine ""
    variable lastDiagnostics ""
}

if {![llength [info commands ::svvs::toolchain::compiler]]} {
    source [file join $::APP_DIR toolchain.tcl]
    ::svvs::toolchain::activate
}

proc ::svvs::simulation_backends::localToolsRoot {} {
    return [lindex [::svvs::toolchain::toolRoots] 0]
}

proc ::svvs::simulation_backends::firstExecutable {paths} {
    foreach path $paths {
        if {$path ne "" && [file exists $path] && ![file isdirectory $path]} {
            return [file normalize $path]
        }
    }
    return ""
}

proc ::svvs::simulation_backends::compilerExecutable {} {
    return [::svvs::toolchain::compiler]
}

proc ::svvs::simulation_backends::ossExecutable {name} {
    return [::svvs::toolchain::ossExecutable $name]
}

proc ::svvs::simulation_backends::cxxrtlInclude {} {
    return [::svvs::toolchain::cxxrtlInclude]
}

proc ::svvs::simulation_backends::cxxrtlIdentifier {name} {
    set result "p_"
    foreach char [split $name ""] {
        if {[regexp {[A-Za-z0-9]} $char]} {
            append result $char
        } elseif {$char eq "_"} {
            append result "__"
        } else {
            scan $char %c code
            append result [format "_%02x_" $code]
        }
    }
    return $result
}

proc ::svvs::simulation_backends::cppString {value} {
    return [string map [list "\\" "\\\\" "\"" "\\\""] $value]
}

proc ::svvs::simulation_backends::removeStaleFiles {directory pattern keep} {
    foreach path [glob -nocomplain -directory $directory -types f $pattern] {
        if {[file normalize $path] ne [file normalize $keep]} {
            catch {file delete -force $path}
        }
    }
}

proc ::svvs::simulation_backends::writeCxxrtlBridge {path model} {
    set allSignals [concat [dict get $model inputs] [dict get $model outputs]]
    foreach signal $allSignals {
        if {[dict get $signal width] > 64} {
            error "CXXRTL live bridge supports ports up to 64 bits; '[dict get $signal name]' is wider."
        }
    }
    set emitLines ""
    foreach signal $allSignals {
        set name [dict get $signal name]
        set field [::svvs::simulation_backends::cxxrtlIdentifier $name]
        append emitLines "    std::cout << \"\\t[::svvs::simulation_backends::cppString $name]=\" << top->$field.template get<unsigned long long>();\n"
    }
    set readyLines ""
    set inputNames {}
    foreach signal [dict get $model inputs] { lappend inputNames [dict get $signal name] }
    foreach signal $allSignals {
        set name [dict get $signal name]
        set direction [expr {$name in $inputNames ? "input" : "output"}]
        append readyLines "        std::cout << \"\\t[::svvs::simulation_backends::cppString $name]:$direction:[dict get $signal width]\";\n"
    }
    set setLines ""
    set first 1
    foreach signal [dict get $model inputs] {
        set name [dict get $signal name]
        set field [::svvs::simulation_backends::cxxrtlIdentifier $name]
        set keyword [expr {$first ? "if" : "else if"}]
        append setLines "                $keyword (part\[1\] == \"[::svvs::simulation_backends::cppString $name]\") { top->$field.set(value); found = true; }\n"
        set first 0
    }
    set template {#include "cxxrtl_model.cpp"
#include <iostream>
#include <cctype>
#include <limits>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
using Top = cxxrtl_design::p_rtl__explorer__top;
static std::unique_ptr<Top> top;
static cxxrtl::debug_items debug;
static std::map<std::string, std::string> watches;
static std::vector<std::string> fields(const std::string &line) {
    std::vector<std::string> result;
    std::stringstream stream(line);
    std::string item;
    while (std::getline(stream, item, '\t')) result.push_back(item);
    return result;
}
static std::string lower(std::string value) {
    for (auto &ch : value) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    return value;
}
static void rebuild_debug() {
    debug.table.clear();
    debug.attrs_table.clear();
    top->debug_info(&debug, nullptr, "");
}
static std::string find_debug_item(const std::string &module, const std::string &signal) {
    const auto module_lower = lower(module);
    const auto signal_lower = lower(signal);
    std::string selected;
    int selected_score = std::numeric_limits<int>::max();
    for (const auto &entry : debug.table) {
        const auto name = lower(entry.first);
        if (name.find(signal_lower) == std::string::npos) continue;
        const int score = (name.find(module_lower) == std::string::npos ? 1000 : 0) + static_cast<int>(name.size());
        if (score < selected_score) { selected = entry.first; selected_score = score; }
    }
    if (selected.empty()) throw std::runtime_error("internal signal not found: " + module + "." + signal);
    return selected;
}
static unsigned long long debug_value(const std::string &name) {
    unsigned long long value = 0;
    const size_t chunk_bits = sizeof(cxxrtl::chunk_t) * 8;
    for (const auto &item : debug.at(name)) {
        if (item.width + item.lsb_at > 64) throw std::runtime_error("internal watch wider than 64 bits");
        for (size_t bit = 0; bit < item.width; ++bit) {
            if ((item.curr[bit / chunk_bits] >> (bit % chunk_bits)) & 1)
                value |= 1ull << (bit + item.lsb_at);
        }
    }
    return value;
}
static void emit_values() {
    std::cout << "VALUES";
@EMIT@    for (const auto &watch : watches) std::cout << "\t" << watch.first << "=" << debug_value(watch.second);
    std::cout << std::endl;
}
int main() {
    try {
        top = std::make_unique<Top>();
        top->step();
        rebuild_debug();
        std::cout << "READY";
@READY@        std::cout << std::endl;
        emit_values();
        std::string line;
        while (std::getline(std::cin, line)) {
            auto part = fields(line);
            if (part.empty()) continue;
            if (part[0] == "QUIT") break;
            if (part[0] == "RESET") {
                top = std::make_unique<Top>();
                top->step();
                rebuild_debug();
            } else if (part[0] == "SET" && part.size() == 3) {
                const auto value = std::stoull(part[2], nullptr, 0);
                bool found = false;
@SET@                if (!found) throw std::runtime_error("unknown input: " + part[1]);
                top->step();
            } else if (part[0] == "EVAL") {
                top->step();
            } else if (part[0] == "WATCH" && part.size() == 4) {
                try {
                    watches[part[1]] = find_debug_item(part[2], part[3]);
                } catch (const std::exception &error) {
                    std::cout << "ERROR\t" << error.what() << std::endl;
                    continue;
                }
            } else {
                throw std::runtime_error("invalid simulation command");
            }
            emit_values();
        }
    } catch (const std::exception &error) {
        std::cout << "ERROR\t" << error.what() << std::endl;
        return 1;
    }
    return 0;
}
}
    set handle [open $path w]
    puts $handle [string map [list @EMIT@ $emitLines @READY@ $readyLines @SET@ $setLines] $template]
    close $handle
}

proc ::svvs::simulation_backends::buildCxxrtl {result} {
    set compiler [::svvs::simulation_backends::compilerExecutable]
    set include [::svvs::simulation_backends::cxxrtlInclude]
    if {$compiler eq ""} { error "C++ compiler not found for CXXRTL." }
    if {$include eq ""} { error "CXXRTL runtime headers not found." }
    if {![dict exists $result cxxrtl] || ![file exists [dict get $result cxxrtl]]} {
        error "Yosys did not generate a CXXRTL model."
    }
    set build [file dirname [dict get $result cxxrtl]]
    set bridge [file join $build cxxrtl_bridge.cpp]
    set suffix [expr {$::tcl_platform(platform) eq "windows" ? ".exe" : ""}]
    set executable [file join $build "cxxrtl_simulator_[pid]${suffix}"]
    ::svvs::simulation_backends::removeStaleFiles $build "cxxrtl_simulator_*${suffix}" $executable
    ::svvs::simulation_backends::writeCxxrtlBridge $bridge [dict get $result model]
    set oldPath $::env(PATH)
    set separator [::svvs::toolchain::pathSeparator]
    set ::env(PATH) "[file dirname $compiler]$separator$oldPath"
    set compilerFlags [list -std=c++17 -O2]
    if {$::tcl_platform(platform) eq "windows"} {
        lappend compilerFlags -static -static-libgcc -static-libstdc++
    }
    set failed [catch {exec $compiler {*}$compilerFlags -I$include $bridge -o $executable 2>@1} output]
    set ::env(PATH) $oldPath
    if {$failed} {
        error "CXXRTL compilation failed:\n$output"
    }
    return [list $executable]
}

proc ::svvs::simulation_backends::writeIcarusTestbench {path model} {
    set lines [list {module rtlx_tb;}]
    foreach direction {inputs outputs} type {reg wire} {
        foreach signal [dict get $model $direction] {
            set width [dict get $signal width]
            set decl [expr {$width > 1 ? [format {[%d:0] } [expr {$width - 1}]] : ""}]
            lappend lines "  $type ${decl}[dict get $signal name];"
        }
    }
    set ports {}
    foreach signal [concat [dict get $model inputs] [dict get $model outputs]] {
        set name [dict get $signal name]
        lappend ports [format ".%s(%s)" $name $name]
    }
    lappend lines "  rtl_explorer_top dut ([join $ports {, }]);"
    lappend lines {  integer fd, status, input_id;}
    lappend lines {  reg [1023:0] stimulus_path;}
    lappend lines {  reg [4095:0] input_value;}
    lappend lines "  initial begin"
    foreach signal [dict get $model inputs] { lappend lines "    [dict get $signal name] = 0;" }
    lappend lines {    if (!$value$plusargs("stimulus=%s", stimulus_path)) $finish;}
    lappend lines {    fd = $fopen(stimulus_path, "r");}
    lappend lines {    if (fd == 0) $finish;}
    lappend lines {    #1;}
    lappend lines {    while (!$feof(fd)) begin}
    lappend lines {      status = $fscanf(fd, "%d %h\n", input_id, input_value);}
    lappend lines {      if (status == 2) begin}
    lappend lines {        case (input_id)}
    set index 0
    foreach signal [dict get $model inputs] {
        lappend lines "          $index: [dict get $signal name] = input_value;"
        incr index
    }
    lappend lines {          default: ;}
    lappend lines {        endcase}
    lappend lines {        #1;}
    lappend lines {      end}
    lappend lines {    end}
    lappend lines {    $fclose(fd);}
    lappend lines {    $write("RTLX_VALUES");}
    foreach signal [concat [dict get $model inputs] [dict get $model outputs]] {
        set name [dict get $signal name]
        lappend lines "    if (^$name === 1'bx) \$write(\"\\t${name}=x\"); else \$write(\"\\t${name}=%0d\", $name);"
    }
    lappend lines {    $write("\n");}
    lappend lines {    $finish;}
    lappend lines {  end}
    lappend lines {endmodule}
    set handle [open $path w]
    puts $handle [join $lines "\n"]
    close $handle
}

proc ::svvs::simulation_backends::buildIcarus {result} {
    set iverilog [::svvs::simulation_backends::ossExecutable iverilog]
    set vvp [::svvs::simulation_backends::ossExecutable vvp]
    set python [::svvs::simulation_model::pythonExecutable]
    if {$iverilog eq "" || $vvp eq ""} { error "Icarus Verilog was not found." }
    if {$python eq ""} { error "Python was not found for the Icarus adapter." }
    if {$::tcl_platform(platform) eq "windows" && [string first " " $iverilog] >= 0} {
        error "Icarus on Windows cannot run from a directory containing spaces. Reinstall RTL Explorer in the default RTLExplorer directory."
    }
    set build [file dirname [dict get $result converted]]
    set testbench [file join $build icarus_bridge.v]
    set compiled [file join $build "icarus_design_[pid].vvp"]
    set stimulus [file join $build "icarus_stimulus_[pid].txt"]
    set metadata [file join $build "icarus_backend_[pid].tsv"]
    ::svvs::simulation_backends::removeStaleFiles $build icarus_design_*.vvp $compiled
    ::svvs::simulation_backends::removeStaleFiles $build icarus_stimulus_*.txt $stimulus
    ::svvs::simulation_backends::removeStaleFiles $build icarus_backend_*.tsv $metadata
    set suiteRoot [file dirname [file dirname $iverilog]]
    ::svvs::simulation_backends::writeIcarusTestbench $testbench [dict get $result model]
    set adapter [file join $::APP_DIR icarus_backend.py]
    set failed [catch {exec $python $adapter --compile $iverilog $suiteRoot $compiled \
        [dict get $result converted] $testbench 2>@1} output]
    if {$failed} {
        error "Icarus compilation failed:\n$output"
    }
    set handle [open $metadata w]
    puts $handle "VVP\t[file normalize $vvp]"
    puts $handle "ROOT\t[file normalize $suiteRoot]"
    puts $handle "DESIGN\t[file normalize $compiled]"
    puts $handle "STIMULUS\t[file normalize $stimulus]"
    foreach direction {inputs outputs} label {INPUT OUTPUT} {
        foreach signal [dict get [dict get $result model] $direction] {
            puts $handle "$label\t[dict get $signal name]\t[dict get $signal width]"
        }
    }
    close $handle
    return [list $python $adapter $metadata]
}

proc ::svvs::simulation_backends::buildPython {result} {
    set python [::svvs::simulation_model::pythonExecutable]
    if {$python eq ""} { error "Python was not found." }
    set script [file join $::APP_DIR netlist_sim.py]
    if {[catch {exec $python $script --check [dict get $result json] \
            $::svvs::simulation_model::topModule 2>@1} output]} {
        error "Python engine cannot safely run this netlist:\n$output"
    }
    return [list $python $script [dict get $result json] $::svvs::simulation_model::topModule]
}

proc ::svvs::simulation_backends::prepare {result} {
    variable selectedEngine
    variable activeEngine
    variable lastDiagnostics
    ::svvs::toolchain::activate
    set engines [expr {$selectedEngine eq "Automatic" ? {CXXRTL Icarus Python} : [list $selectedEngine]}]
    set failures {}
    set builders [dict create CXXRTL buildCxxrtl Icarus buildIcarus Python buildPython]
    foreach engine $engines {
        set commandName "::svvs::simulation_backends::[dict get $builders $engine]"
        if {![catch {set command [$commandName $result]} message]} {
            set activeEngine $engine
            set lastDiagnostics [join $failures "\n"]
            return [dict create ok 1 engine $engine command $command diagnostics $lastDiagnostics]
        }
        lappend failures "$engine: $message"
    }
    set activeEngine ""
    set lastDiagnostics [join $failures "\n"]
    return [dict create ok 0 engine "" message $lastDiagnostics diagnostics $lastDiagnostics]
}
