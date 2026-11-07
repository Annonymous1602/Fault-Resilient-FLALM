#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs
iverilog -g2012 -s karatsuba_security_tb -o build/monitor_tb.vvp \
 secure_rtl/*.v security/karatsuba_residue_monitor.v tb/karatsuba_security_tb.v
vvp build/monitor_tb.vvp | tee logs/monitor_tb.log
