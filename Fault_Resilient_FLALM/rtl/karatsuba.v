// B5  karatsuba : reused and parallel Karatsuba multiplication
//
// Paper : Alg. 5, Eq. 7/8/17/18/24, Fig. 6, Table IV
// Spec  : FLALM_SPEC 5 and 6.3; A16 (M_Res2 is W+1 bits, (W+1)-bit SUB mod 2^(W+1));
//         A25 (sync reset on control state only); A30 (ADD1/ADD2/SUB built from bka)
// Golden: model/datapath.py karatsuba(); timing = model/cycle_model.py / Table IV
//
// One operation is issued in cycle c (issue = 1, a/b valid).  Issues must be at
// least 3 cycles apart (the FSM issues every 3 cycles).  Per operation:
//
//   end c   : r-a1, r-a0, r-b1, r-b0 <- a, b ;  mi <- (a0, b0)
//   c+1     : ADD1/ADD2 t1 = a1+a0, t2 = b1+b0 ; MUL cycle-1 (a0b0)
//             end: mi <- (t1, t2)
//   c+2     : MUL cycle-1 (t1t2), MUL cycle-2 (a0b0) ; end: r1 <- m_o, mi <- (r-a1, r-b1)
//   c+3     : MUL cycle-1 (a1b1), MUL cycle-2 (t1t2) ; end: r2 <- m_o
//   c+4     : MUL cycle-2 (a1b1), SUB                ; end: r3 <- m_o, r2 <- r2 - r1
//   c+5     : SUB ; M_Res1 = (r3, r1) valid          ; end: r2 <- r2 - r3
//   c+6     : M_Res2 = r2 valid
//
// KMUL-STATE (Table VII) "r1/r2/r3" = the product in MUL cycle-1 = vld[1]/vld[2]/vld[3].
module karatsuba #(
    parameter W = 128
) (
    input              clk,
    input              rst,          // synchronous, control state only
    input              issue,        // cycle c: a, b valid
    input  [W-1:0]     a,
    input  [W-1:0]     b,
    output [2*W-1:0]   m_res1,       // (r3, r1): valid in cycle c+5
    output [W:0]       m_res2,       // r2      : valid in cycle c+6
    output             m_res1_vld,   // 1 in cycle c+5
    output             security_fault_out
);
    localparam H = W / 2;

    // vld[k] = 1 in cycle c+k of an issued operation
    reg [5:1] vld;
    always @(posedge clk) begin
        if (rst) vld <= 5'b0;
        else     vld <= {vld[4:1], issue};
    end

    // ---------------- operand registers (r-a1, r-a0, r-b1, r-b0) ----------------
    reg [H-1:0] r_a1, r_a0, r_b1, r_b0;
    always @(posedge clk) begin
        if (issue) begin
            r_a1 <= a[W-1:H];
            r_a0 <= a[H-1:0];
            r_b1 <= b[W-1:H];
            r_b0 <= b[H-1:0];
        end
    end

    // ---------------- ADD1 / ADD2: (W/2)-bit adders ----------------
    wire [H:0] t1, t2;
    assign t1 = {1'b0, r_a1} + {1'b0, r_a0};
    assign t2 = {1'b0, r_b1} + {1'b0, r_b0};

    // ---------------- MUX-1 / MUX-2 -> mi1 / mi2 (a0 -> t1 -> r-a1) ----------------
    reg [H:0] mi1, mi2;
    always @(posedge clk) begin
        if (issue) begin
            mi1 <= {1'b0, a[H-1:0]};
            mi2 <= {1'b0, b[H-1:0]};
        end else if (vld[1]) begin
            mi1 <= t1;
            mi2 <= t2;
        end else if (vld[2]) begin
            mi1 <= {1'b0, r_a1};
            mi2 <= {1'b0, r_b1};
        end
    end

    // ---------------- 2-cycle MUL ----------------
    wire [W+1:0] m_o;
    mul2c #(.W(W)) u_mul (
        .clk(clk),
        .en (vld[1] | vld[2] | vld[3]),
        .mi1(mi1),
        .mi2(mi2),
        .m_o(m_o)
    );

    // ---------------- r1 / r2 / r3 and the (W+1)-bit SUB ----------------
    reg [W-1:0] r1, r3;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [W+1:0] r2;             // (W+2)-bit capture of t1*t2; W+1 bits after SUB
    /* verilator lint_on UNUSEDSIGNAL */

    wire [W:0] sub_y = vld[4] ? {1'b0, r1} : {1'b0, r3};
    wire [W:0] sub_s;
    /* verilator lint_off UNUSEDSIGNAL */
    wire       sub_cout;        // mod 2^(W+1)
    /* verilator lint_on UNUSEDSIGNAL */
    assign sub_s = r2[W:0] - sub_y;
    assign sub_cout = 1'b0;

    always @(posedge clk) begin
        if (vld[2]) r1 <= m_o[W-1:0];                  // a0*b0 < 2^W
        if (vld[4]) r3 <= m_o[W-1:0];                  // a1*b1 < 2^W
        if (vld[3])               r2 <= m_o;           // t1*t2
        else if (vld[4] | vld[5]) r2 <= {1'b0, sub_s}; // mod 2^(W+1)
    end

    assign m_res1     = {r3, r1};
    assign m_res2     = r2[W:0];
    assign m_res1_vld = vld[5];


    // ============================================================
    // Phase 19A: Independent r3 residue verification
    //
    // r3 = a_high * b_high.
    //
    // Expected residue is captured at issue and delayed until
    // the corresponding r3 register is valid.
    //
    // This check is independent of the reconstructed-product
    // residue, avoiding cancellation between r2 and r3.
    // ============================================================


    // ============================================================
    // Phase 20 D2-O1:
    // Pipelined independent r3 residue verification.
    //
    // Modulus P = 8191.
    //
    // Issue edge c:
    //   Capture residues of upper operand halves.
    //
    // Edge c+1:
    //   Capture 13x13 residue product.
    //
    // Edge c+2:
    //   Capture reduced expected residue.
    //
    // Edges c+3, c+4:
    //   Delay expected residue.
    //
    // Edge c+5:
    //   Compare against actual r3 residue.
    //
    // No additional functional multiplication cycles.
    // ============================================================

    // ------------------------------------------------------------
    // Stage 0: Upper-half operand residue reduction
    // ------------------------------------------------------------

    wire [12:0] r3_ah_residue;
    wire [12:0] r3_bh_residue;

    residue_fold_8191 #(.W(H)) u_r3_red_ah (
        .x(a[W-1:H]),
        .residue(r3_ah_residue)
    );

    residue_fold_8191 #(.W(H)) u_r3_red_bh (
        .x(b[W-1:H]),
        .residue(r3_bh_residue)
    );

    (* DONT_TOUCH = "true" *) reg [12:0] r3_ah_residue_reg;
    (* DONT_TOUCH = "true" *) reg [12:0] r3_bh_residue_reg;

    // ------------------------------------------------------------
    // Stage 1: Residue multiplication
    // ------------------------------------------------------------

    wire [25:0] r3_expected_product =
        r3_ah_residue_reg * r3_bh_residue_reg;

    reg [25:0] r3_expected_product_reg;

    // ------------------------------------------------------------
    // Stage 2: Modulo-8191 reduction
    // ------------------------------------------------------------

    wire [12:0] r3_expected_residue;

    residue_fold_8191 #(.W(26)) u_r3_red_expected (
        .x(r3_expected_product_reg),
        .residue(r3_expected_residue)
    );

    // ------------------------------------------------------------
    // Actual r3 residue
    // ------------------------------------------------------------

    // Original residue observation retained for compatibility.
    // The correlated-fault testbench can mask this signal.
    wire [12:0] r3_actual_residue;

    residue_fold_8191 #(.W(W)) u_r3_red_actual (
        .x(r3),
        .residue(r3_actual_residue)
    );

    // P2: independent observation of the functional r3 register.
    // This path must not consume r3_actual_residue.
    // Preserve the distinct reducer during synthesis.
    wire [12:0] r3_actual_residue_independent;

    (* DONT_TOUCH = "true" *)
    residue_fold_8191 #(.W(W)) u_r3_red_actual_independent (
        .x(r3),
        .residue(r3_actual_residue_independent)
    );

    // Three delay registers:
    //
    // expected_pipe[0] receives result at c+2
    // expected_pipe[1] receives result at c+3
    // expected_pipe[2] receives result at c+4
    //
    // At c+5, comparison reads expected_pipe[2].

    reg [12:0] r3_expected_pipe [0:2];

    reg r3_residue_fault;

    integer r3_pipe_i;

    always @(posedge clk) begin

        if (rst) begin

            r3_ah_residue_reg <= 13'd0;
            r3_bh_residue_reg <= 13'd0;

            r3_expected_product_reg <= 26'd0;

            for (r3_pipe_i = 0;
                 r3_pipe_i < 3;
                 r3_pipe_i = r3_pipe_i + 1)
                r3_expected_pipe[r3_pipe_i] <= 13'd0;

            r3_residue_fault <= 1'b0;

        end else begin

            // Stage 0: Capture upper-half residues.
            // D2-O2D-D:
            // Capture operand residues only for issued operations.
            if (issue) begin
                r3_ah_residue_reg <= r3_ah_residue;
                r3_bh_residue_reg <= r3_bh_residue;
            end

            // Stage 1: Capture residue multiplication.
            r3_expected_product_reg <= r3_expected_product;

            // Stage 2: Capture reduced expected residue.
            r3_expected_pipe[0] <= r3_expected_residue;

            // Expected-residue alignment.
            r3_expected_pipe[1] <= r3_expected_pipe[0];
            r3_expected_pipe[2] <= r3_expected_pipe[1];

            // The actual r3 result and expected residue
            // correspond to the same issued multiplication.
            // Compare the independent observation, not the
            // potentially masked shared residue signal.
            if (vld[5] &&
                (r3_actual_residue_independent !== r3_expected_pipe[2]))
                r3_residue_fault <= 1'b1;

        end
    end

    // Security monitor, kept outside the functional arithmetic path.
    wire security_fault;
    assign security_fault_out =
        security_fault | r3_residue_fault;
    wire security_checked;
    wire [31:0] security_checks;
    karatsuba_residue_monitor #(.W(W), .P(8191)) u_security_residue (
        .clk(clk), .rst(rst), .issue(issue), .a(a), .b(b),

        // Reuse registered upper-half operand residues.
        .upper_a_residue(r3_ah_residue_reg),
        .upper_b_residue(r3_bh_residue_reg),

        .m_res1(m_res1), .m_res2(m_res2), .m_res1_vld(m_res1_vld),
        .alarm(security_fault), .checked(security_checked),
        .checks(security_checks)
    );


    // synthesis translate_off
    always @(posedge clk) begin
        if (!rst && issue && (vld[1] | vld[2]))
            $display("ERROR karatsuba: issue less than 3 cycles after the previous one (t=%0t)",
                     $time);
    end
    // synthesis translate_on
endmodule
