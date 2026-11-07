if {$argc != 1} {
    error "Usage: baseline|secure"
}

set variant [lindex $argv 0]

set root [pwd]
set dcp [file join $root results implementation $variant routed.dcp]

open_checkpoint $dcp

set outdir [file join $root results implementation $variant]

report_timing \
    -delay_type max \
    -max_paths 20 \
    -path_type full \
    -input_pins \
    -nets \
    -file [file join $outdir critical_paths.txt]

puts "CRITICAL_PATH_REPORT_DONE $variant"

exit
