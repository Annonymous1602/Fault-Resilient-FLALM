if {$argc != 1} {
    error "Usage: baseline|secure"
}

set variant [lindex $argv 0]

if {$variant ne "baseline" && $variant ne "secure"} {
    error "Invalid variant"
}

set root [pwd]
set src_checkpoint [file join $root results synthesis "${variant}_8words_synth.dcp"]

set outdir [file join $root results implementation $variant]
file mkdir $outdir

open_checkpoint $src_checkpoint

report_utilization \
    -file [file join $outdir utilization_before_implementation.txt]

opt_design

place_design

phys_opt_design

route_design

report_utilization \
    -file [file join $outdir utilization_routed.txt]

report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -file [file join $outdir timing_routed.txt]

report_design_analysis \
    -timing \
    -file [file join $outdir design_analysis.txt]

report_power \
    -file [file join $outdir power_routed.txt]

write_checkpoint -force \
    [file join $outdir routed.dcp]

puts "IMPLEMENTATION_DONE $variant"
