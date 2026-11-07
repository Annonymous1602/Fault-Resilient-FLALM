`timescale 1ns/1ps

module recover_variable_bit_tb;

    localparam W = 128;
    localparam NW = 8;
    localparam N = 1024;
    localparam AW = $clog2(4*NW);
    localparam KW = $clog2(NW+1);

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;

    reg host_we = 0;
    reg [AW-1:0] host_addr = 0;
    reg [W-1:0] host_data = 0;

    reg [KW-1:0] len = NW;
    reg smm_en = 0;
    reg [W-1:0] mp = 0;

    wire busy;
    wire done;
    wire result_valid;
    wire recovery_success;
    wire recovery_failed;
    wire fault_seen;
    wire z_sel;

    reg [N-1:0] vectors [0:4];
    reg [N-1:0] result_got;

    reg [8*512-1:0] vector_file;

    integer i;
    integer cycles;

    flalm_recover #(
        .W(W),
        .NW(NW)
    ) dut (
        .clk(clk),
        .rst(rst),

        .host_we(host_we),
        .host_addr(host_addr),
        .host_data(host_data),

        .start(start),
        .len(len),
        .smm_en(smm_en),
        .mp(mp),

        .busy(busy),
        .done(done),
        .result_valid(result_valid),
        .recovery_success(recovery_success),
        .recovery_failed(recovery_failed),
        .fault_seen(fault_seen),
        .z_sel(z_sel)
    );



    reg first_attempt_captured = 0;
    reg [N-1:0] first_attempt_result;
    integer word_index;

    // Observe the first attempt before the recovery reloads RAM.
    always @(posedge clk) begin

        if (!rst &&
            attempt_count == 1 &&
            dut.core_done &&
            !first_attempt_captured) begin

            first_attempt_captured = 1;

            // Allow pending nonblocking writes to settle.
            #1;

            first_attempt_result = 0;

            for (word_index = 0;
                 word_index < NW;
                 word_index = word_index + 1) begin

                if (dut.core_z_sel)
                    first_attempt_result[word_index*W +: W] =
                        dut.u_ram.mem[NW + word_index];
                else
                    first_attempt_result[word_index*W +: W] =
                        dut.u_ram.mem[word_index];

            end

            if (first_attempt_result !== vectors[4])
                $display("FIRST_ATTEMPT_RESULT_CORRUPTED=1");
            else
                $display("FIRST_ATTEMPT_RESULT_CORRUPTED=0");

            $display(
                "FIRST_ATTEMPT_ALARM=%b",
                dut.core_fault
            );

            $display(
                "FIRST_ATTEMPT_RESULT=%h",
                first_attempt_result
            );

            $display(
                "EXPECTED_RESULT=%h",
                vectors[4]
            );

        end

    end

    integer attempt_count = 0;
    reg injected = 0;
    integer fault_bit = 0;

    integer fault_op_index = 1;
    integer op_seen = 0;
    integer injected_op_index = 0;
    

    initial begin
        if ($value$plusargs("fault_bit=%d", fault_bit)) begin
            if (fault_bit < 0 || fault_bit >= 128) begin
                $display("INVALID_FAULT_BIT=%0d", fault_bit);
                $fatal(1);
            end
        end
    end



    initial begin
        if ($value$plusargs(
            "fault_op_index=%d", fault_op_index
        )) begin
            if (fault_op_index < 1 ||
                fault_op_index > 100000) begin

                $display(
                    "INVALID_FAULT_OP_INDEX=%0d",
                    fault_op_index
                );

                $fatal(1);
            end
        end

        $display(
            "REQUESTED_FAULT_OP_INDEX=%0d",
            fault_op_index
        );
    end

    // Count the actual FLALM execution attempts.
    always @(posedge clk) begin
        if (!rst && dut.core_start) begin
            attempt_count = attempt_count + 1;

            $display(
                "RECOVERY_ATTEMPT_START count=%0d time=%0t",
                attempt_count, $time
            );
        end
    end


    // ============================================================
    // D2-O2C CORRELATED DATAPATH/CHECKER FAULT
    //
    // Fault A:
    //   Flip one bit of the r3 multiplication result.
    //
    // Fault B:
    //   Force the shared observed r3 residue to its original
    //   fault-free value during the checker sampling edge.
    //
    // This is a deliberate two-location fault experiment.
    // ============================================================


    // Phase 25D spatial fault experiment.
    // Target: r2
    //
    // This testbench modifies simulation state only.
    // The frozen DUT RTL remains unchanged.

    reg [129:0] original_target;
    reg [129:0] faulty_target;

    integer injection_time = 0;

    always @(negedge clk) begin

        if (!rst &&
            attempt_count == 1 &&
            dut.state == 3'd3) begin

            // Count completed Karatsuba product events.
            if (dut.u_core.u_pe.u_kar.m_res1_vld)
                op_seen = op_seen + 1;

            // The selected injection window is different
            // for r1 and reconstructed r2.
            if (!injected &&
                op_seen == fault_op_index &&
                dut.u_core.u_pe.u_kar.u_security_residue.late_valid) begin

                original_target = dut.u_core.u_pe.u_kar.r2;

                faulty_target =
                    original_target ^
                    (130'd1 << fault_bit);

                injected_op_index = op_seen;
                injected = 1;

                // Transient register-state corruption.
                dut.u_core.u_pe.u_kar.r2 = faulty_target;

                #1;

                if (dut.u_core.u_pe.u_kar.r2 !== faulty_target) begin
                    $display("SPATIAL_INJECTION_FAIL");
                    $fatal(1);
                end

                $display("SPATIAL_TARGET=r2");
                $display(
                    "SPATIAL_OPERATION_INDEX=%0d",
                    injected_op_index
                );
                $display(
                    "SPATIAL_FAULT_BIT=%0d",
                    fault_bit
                );
                $display(
                    "SPATIAL_ORIGINAL=%h",
                    original_target
                );
                $display(
                    "SPATIAL_FAULTY=%h",
                    faulty_target
                );
                $display(
                    "SPATIAL_NONZERO=%0d",
                    original_target != 0
                );
                $display(
                    "SPATIAL_INJECTION_TIME=%0t",
                    $time
                );

            end
        end
    end

    // Existing checker trace follows.
    integer correlated_trace_count = 0;

    always @(posedge clk) begin
        if (!rst && injected && correlated_trace_count < 16) begin
            #1;

            correlated_trace_count = correlated_trace_count + 1;

            $display(
                "CORRELATED_CHECKER_TRACE count=%0d vld=%b independent=%b combined=%b aggregate=%b r3_residue=%h expected=%h",
                correlated_trace_count,
                dut.u_core.u_pe.u_kar.vld,
                dut.u_core.u_pe.u_kar.r3_residue_fault,
                dut.u_core.u_pe.u_kar.u_security_residue.alarm,
                dut.u_core.u_pe.u_kar.security_fault_out,
                dut.u_core.u_pe.u_kar.r3_actual_residue,
                dut.u_core.u_pe.u_kar.r3_expected_pipe[2]
            );

            $display(
                "CORRELATED_COMBINED_TRACE count=%0d valid=%b observed=%h expected=%h part1=%h part2=%h alarm=%b",
                correlated_trace_count,
                dut.u_core.u_pe.u_kar.u_security_residue.valid_pipe[6],
                dut.u_core.u_pe.u_kar.u_security_residue.observed,
                dut.u_core.u_pe.u_kar.u_security_residue.expected_pipe[3],
                dut.u_core.u_pe.u_kar.u_security_residue.part1_residue,
                dut.u_core.u_pe.u_kar.u_security_residue.part2_residue,
                dut.u_core.u_pe.u_kar.u_security_residue.alarm
            );
            $display("P1_PIPE valid_pipe=%b late_valid=%b expected0=%h expected1=%h expected2=%h expected3=%h part1=%h part2=%h observed=%h alarm=%b",
                dut.u_core.u_pe.u_kar.u_security_residue.valid_pipe,
                dut.u_core.u_pe.u_kar.u_security_residue.late_valid,
                dut.u_core.u_pe.u_kar.u_security_residue.expected_pipe[0],
                dut.u_core.u_pe.u_kar.u_security_residue.expected_pipe[1],
                dut.u_core.u_pe.u_kar.u_security_residue.expected_pipe[2],
                dut.u_core.u_pe.u_kar.u_security_residue.expected_pipe[3],
                dut.u_core.u_pe.u_kar.u_security_residue.part1_residue,
                dut.u_core.u_pe.u_kar.u_security_residue.part2_residue,
                dut.u_core.u_pe.u_kar.u_security_residue.observed,
                dut.u_core.u_pe.u_kar.u_security_residue.alarm
            );

        end
    end

    initial begin

        if (!$value$plusargs("vectors=%s", vector_file)) begin
            $display("RECOVERY_SMOKE_FAIL missing vectors");
            $fatal(1);
        end

        $readmemh(vector_file, vectors);

        repeat (4) @(negedge clk);

        rst = 0;

        // Load original X.
        for (i = 0; i < NW; i = i + 1) begin

            @(negedge clk);

            host_we = 1;
            host_addr = i;
            host_data = vectors[0][i*W +: W];

        end

        // Load original Y.
        for (i = 0; i < NW; i = i + 1) begin

            @(negedge clk);

            host_we = 1;
            host_addr = NW+i;
            host_data = vectors[1][i*W +: W];

        end

        // Load original modulus.
        for (i = 0; i < NW; i = i + 1) begin

            @(negedge clk);

            host_we = 1;
            host_addr = 2*NW+i;
            host_data = vectors[2][i*W +: W];

        end

        @(negedge clk);

        host_we = 0;
        host_addr = 0;
        host_data = 0;

        mp = vectors[3][W-1:0];

        start = 1;

        @(negedge clk);
        start = 0;

        cycles = 0;

        while (!done && cycles < 1000) begin

            @(negedge clk);
            cycles = cycles + 1;

        end

        if (!done) begin

            $display("RECOVERY_SMOKE_FAIL timeout");
            $fatal(1);

        end


        // ========================================================
        // CORRELATED FAULT CLASSIFICATION
        //
        // Do not require recovery_success unconditionally.
        // An undetected correlated fault is one of the outcomes
        // that this experiment is designed to discover.
        // ========================================================

        if (!injected) begin
            $display("CORRELATED_TEST_INVALID_NO_INJECTION");
            $fatal(1);
        end

        result_got = 0;

        for (i = 0; i < NW; i = i + 1) begin
            result_got[i*W +: W] =
                z_sel
                ? dut.u_ram.mem[NW+i]
                : dut.u_ram.mem[i];
        end

        $display("==========================================");
        $display("CORRELATED FAULT EXPERIMENT");
        $display("==========================================");


        $display("FAULT_BIT=%0d", fault_bit);
        $display("FAULT_SITE=r2");

        $display("REQUESTED_OPERATION=%0d", fault_op_index);
        $display("INJECTED_OPERATION=%0d", injected_op_index);
        $display("OPERATIONS_OBSERVED=%0d", op_seen);
        $display("INJECTION_OCCURRED=%0d", injected);
        $display("ATTEMPTS=%0d", attempt_count);
        $display("CYCLES=%0d", cycles);

        $display("FAULT_SEEN=%b", fault_seen);
        $display("RECOVERY_SUCCESS=%b", recovery_success);
        $display("RECOVERY_FAILED=%b", recovery_failed);

        $display("RESULT_VALID=%b", result_valid);

        if (first_attempt_captured) begin
            $display(
                "FIRST_ATTEMPT_CORRUPTED=%0d",
                first_attempt_result !== vectors[4]
            );
        end else begin
            $display("FIRST_ATTEMPT_CAPTURE_MISSING=1");
        end

        $display("FINAL_RESULT=%h", result_got);
        $display("EXPECTED_RESULT=%h", vectors[4]);

        if (result_valid === 1'b1 &&
            result_got !== vectors[4]) begin

            $display(
                "CORRELATED_CLASSIFICATION=SILENT_DATA_CORRUPTION"
            );

            $display("CORRELATED_SDC_CONFIRMED");

        end else if (result_valid === 1'b1 &&
                     result_got === vectors[4] &&
                     recovery_success === 1'b1 &&
                     attempt_count == 2) begin

            $display("CORRELATED_CLASSIFICATION=RECOVERED");
            $display("CORRELATED_RECOVERY_PASS");

        end else if (result_valid === 1'b0 &&
                     recovery_failed === 1'b1 &&
                     attempt_count == 2) begin

            $display("CORRELATED_CLASSIFICATION=FAIL_CLOSED");

        end else if (result_valid === 1'b1 &&
                     result_got === vectors[4] &&
                     attempt_count == 1) begin

            $display("CORRELATED_CLASSIFICATION=INEFFECTIVE_FAULT");

        end else begin

            $display("CORRELATED_CLASSIFICATION=OTHER_OUTCOME");

        end

        $display("CORRELATED_EXPERIMENT_COMPLETE");

        $finish;

    end

    initial begin

        #20000;

        $display("RECOVERY_SMOKE_FAIL watchdog");
        $fatal(1);

    end


    // Simulation-only checker contribution ablation.
    // Freeze only the specified detector output low.
    initial begin
        #1;
        force dut.u_core.u_pe.u_kar.security_fault = 1'b0;
        $display("ABLATION_MODE=independent_only");
    end

endmodule
