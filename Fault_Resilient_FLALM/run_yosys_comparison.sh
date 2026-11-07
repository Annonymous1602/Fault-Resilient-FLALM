#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p results/yosys logs/yosys

for NW in 8 16
do

    for VARIANT in baseline secure
    do

        echo "===================================="
        echo "Variant: $VARIANT"
        echo "NW: $NW"
        echo "W: 128"
        echo "===================================="

        if [ "$VARIANT" = "baseline" ]; then
            SRCDIR="baseline/rtl"
            TOP="flalm"
        else
            SRCDIR="synth_secure_rtl"
            TOP="flalm_secure"
        fi

        LOG="logs/yosys/${VARIANT}_${NW}.log"

        if [ "$VARIANT" = "secure" ]; then
            EXTRA="security/karatsuba_residue_monitor.v"
        else
            EXTRA=""
        fi

        yosys -l "$LOG" -p "
            read_verilog ${SRCDIR}/*.v ${EXTRA}
            hierarchy -check -top ${TOP} -chparam W 128 -chparam NW ${NW}
            proc
            opt
            check
            flatten
            opt
            techmap
            opt
            stat
            write_json results/yosys/${VARIANT}_${NW}.json
        "

        echo "Finished $VARIANT NW=$NW"

    done

done

echo "All preliminary synthesis runs completed"
