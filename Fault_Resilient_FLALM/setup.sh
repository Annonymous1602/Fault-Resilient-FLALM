#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p baseline/rtl baseline/tb build logs results
shopt -s nullglob
sources=(../rtl/*.v)
if (( ${#sources[@]} == 0 )); then echo 'ERROR: execute this starter from FLALM/security_starter and put original files in FLALM/rtl'; exit 1; fi
cp -n ../rtl/*.v baseline/rtl/
cp -n ../tb/flalm_tb_1024.v ../tb/flalm_tb_2048.v baseline/tb/
printf 'Frozen sources: '; find baseline/rtl -maxdepth 1 -name '*.v' | wc -l
sha256sum baseline/rtl/*.v baseline/tb/*.v > results/baseline_sha256.txt
