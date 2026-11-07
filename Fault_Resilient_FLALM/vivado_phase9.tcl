if {$argc != 2} {error "Usage: baseline|secure NW"}
set variant [lindex $argv 0]
set nw [lindex $argv 1]
set part xcku5p-ffvb676-2-e
set srcdir [expr {$variant eq "baseline" ? "baseline/rtl" : "synth_secure_rtl"}]
read_verilog [glob [file join [pwd] $srcdir *.v]]
if {$variant eq "secure"} {
    read_verilog security/karatsuba_residue_monitor.v
    read_verilog security/residue_fold_8191.v}
set top [expr {$variant eq "baseline" ? "flalm" : "flalm_secure"}]
synth_design -top $top -part $part -generic W=128 -generic NW=$nw -flatten_hierarchy rebuilt
create_clock -period 10.0 -name clk [get_ports clk]
set dir [file join [pwd] results synthesis]
file mkdir $dir
set tag "${variant}_${nw}words"
report_utilization -file [file join $dir "${tag}_util.txt"]
report_timing_summary -file [file join $dir "${tag}_timing_synth.txt"]
write_checkpoint -force [file join $dir "${tag}_synth.dcp"]
puts "SYNTH_DONE $tag"
