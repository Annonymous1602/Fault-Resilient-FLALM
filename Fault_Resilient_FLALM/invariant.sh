#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs
iverilog -g2012 -s mont_lowword_check_tb -o build/invariant.vvp security/mont_lowword_check.v tb/mont_lowword_check_tb.v
vvp build/invariant.vvp | tee logs/invariant.log
