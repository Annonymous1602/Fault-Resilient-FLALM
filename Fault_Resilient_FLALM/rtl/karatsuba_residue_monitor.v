// Phase 14: Residue-only partial-product storage.
//
// Preserves Phase 13 expected-residue pipeline.
// Replaces wide partial-product reconstruction with modular arithmetic.
//
// Modulus: 8191 = 2^13 - 1
//
// m_res1 valid: issue + 5
// m_res2 valid: issue + 6
// Comparison:   issue + 7

module karatsuba_residue_monitor #(
    parameter W = 128,
    parameter P = 8191
)(
    input clk,
    input rst,
    input issue,

    input [W-1:0] a,
    input [W-1:0] b,

    // Registered upper-half operand residues from r3 checker.
    input [12:0] upper_a_residue,
    input [12:0] upper_b_residue,

    input [2*W-1:0] m_res1,
    input [W:0] m_res2,
    input m_res1_vld,

    output reg alarm,
    output reg checked,
    output reg [31:0] checks
);

    localparam RES_W = 13;
    localparam ROT = (W/2) % RES_W;

    // ============================================================
    // Expected residue pipeline (retained from Phase 13)
    // ============================================================

    // D2-O2D-A:
    // Capture only lower-half residues instead of
    // retaining the complete input operands.
    reg [12:0] lower_a_residue_reg;
    reg [12:0] lower_b_residue_reg;

    // ============================================================
    // Phase 20 D2-O2B: Shared upper-half operand residues
    //
    // For P = 8191:
    //
    // 2^(W/2) mod P = 2^ROT mod P.
    //
    // The independent r3 checker already registers the
    // upper-half operand residues.
    //
    // Reduce only the lower halves locally.
    // ============================================================

    localparam HALF_W = W / 2;

    wire [12:0] lower_a_residue;
    wire [12:0] lower_b_residue;

    residue_fold_8191 #(.W(HALF_W)) red_a_lower (
        .x(a[HALF_W-1:0]),
        .residue(lower_a_residue)
    );

    residue_fold_8191 #(.W(HALF_W)) red_b_lower (
        .x(b[HALF_W-1:0]),
        .residue(lower_b_residue)
    );

    // Multiplication by 2^ROT modulo 8191 is a
    // circular rotation of the 13-bit residue.

    wire [12:0] shifted_upper_a;
    wire [12:0] shifted_upper_b;

    assign shifted_upper_a =
        (upper_a_residue << ROT) |
        (upper_a_residue >> (RES_W-ROT));

    assign shifted_upper_b =
        (upper_b_residue << ROT) |
        (upper_b_residue >> (RES_W-ROT));

    wire [13:0] a_residue_sum;
    wire [13:0] b_residue_sum;

    assign a_residue_sum =
        {1'b0, lower_a_residue_reg} +
        {1'b0, shifted_upper_a};

    assign b_residue_sum =
        {1'b0, lower_b_residue_reg} +
        {1'b0, shifted_upper_b};

    wire [12:0] ar_wire;
    wire [12:0] br_wire;

    assign ar_wire =
        (a_residue_sum >= 14'd8191)
        ? (a_residue_sum - 14'd8191)
        : a_residue_sum[12:0];

    assign br_wire =
        (b_residue_sum >= 14'd8191)
        ? (b_residue_sum - 14'd8191)
        : b_residue_sum[12:0];

    reg [12:0] ar_reg;
    reg [12:0] br_reg;

    reg [25:0] small_product_reg;

    wire [12:0] expected_wire;

    residue_fold_8191 #(.W(26)) red_expected (
        .x(small_product_reg),
        .residue(expected_wire)
    );

    reg [12:0] expected_pipe [0:3];


    // ============================================================
    // Observed residue pipeline (new Phase 14 architecture)
    // ============================================================

    // Reduce m_res1 directly instead of storing 256 bits.

    wire [12:0] part1_wire;

    // ============================================================
    // D2-O2C: Shared observed-r3 residue
    //
    // m_res1 = {r3, r1}
    //
    // m_res1 mod 8191 =
    //   (r1_residue + 2^W * r3_residue) mod 8191
    //
    // The actual r3 residue comes from the independent checker.
    // ============================================================

    localparam PART1_ROT = W % RES_W;

    // Independently reduce the actual upper product from m_res1.
    // Do not consume the other checker's r3_actual_residue signal.
    //
    // DONT_TOUCH is intended to preserve a distinct reducer instance.
    // Verify the mapped netlist to ensure the implementation retains it.
    wire [12:0] r3_residue_independent;

    (* DONT_TOUCH = "true" *)
    residue_fold_8191 #(.W(W)) red_independent_r3 (
        .x(m_res1[2*W-1:W]),
        .residue(r3_residue_independent)
    );

    wire [12:0] r1_residue;

    // D2-O2D-C: shared partial-product residue reduction.
    //
    // m_res1_vld: reduce r1 (W bits).
    // late_valid: reduce m_res2 (W+1 bits).
    //
    // The two valid windows are consecutive, not overlapping.

    wire [W:0] shared_reducer_input;

    assign shared_reducer_input =
        m_res1_vld
        ? {1'b0, m_res1[W-1:0]}
        : m_res2;

    wire [12:0] shared_reducer_residue;

    residue_fold_8191 #(.W(W+1)) red_shared_partial (
        .x(shared_reducer_input),
        .residue(shared_reducer_residue)
    );

    assign r1_residue = shared_reducer_residue;

    wire [12:0] rotated_r3;

    assign rotated_r3 =
        (r3_residue_independent << PART1_ROT) |
        (r3_residue_independent >> (RES_W-PART1_ROT));

    wire [13:0] part1_sum;

    assign part1_sum =
        {1'b0, r1_residue} +
        {1'b0, rotated_r3};

    assign part1_wire =
        (part1_sum >= 14'd8191)
        ? part1_sum - 14'd8191
        : part1_sum[12:0];


    // Reduce m_res2 directly instead of storing 129 bits.

    wire [12:0] part2_wire;

    assign part2_wire = shared_reducer_residue;


    // Only store 13-bit residues.

    reg [12:0] part1_residue;
    reg [12:0] part2_residue;

    reg late_valid;


    // ============================================================
    // Modular shift:
    //
    // 2^(W/2) mod 8191
    //
    // Since 2^13 == 1 (mod 8191), multiplication by
    // 2^ROT is a 13-bit cyclic rotation.
    // ============================================================

    wire [12:0] shifted_part2;

    assign shifted_part2 =
        (part2_residue << ROT) |
        (part2_residue >> (RES_W-ROT));


    // ============================================================
    // Modular addition
    // ============================================================

    wire [13:0] residue_sum;

    assign residue_sum =
        {1'b0, part1_residue} +
        {1'b0, shifted_part2};

    wire [12:0] observed;

    assign observed =
        (residue_sum >= 14'd8191)
        ? residue_sum - 14'd8191
        : residue_sum[12:0];


    // ============================================================
    // Pipeline control
    // ============================================================

    reg [6:0] valid_pipe;

    integer i;

    always @(posedge clk) begin

        if (rst) begin

            lower_a_residue_reg <= 13'd0;
            lower_b_residue_reg <= 13'd0;

            ar_reg <= 0;
            br_reg <= 0;

            small_product_reg <= 0;

            for (i = 0; i < 4; i = i + 1)
                expected_pipe[i] <= 0;

            part1_residue <= 0;
            part2_residue <= 0;

            late_valid <= 0;
            valid_pipe <= 0;

            alarm <= 0;
            checked <= 0;
            checks <= 0;

        end else begin

            // Expected residue computation.

            // Capture lower operand residues only on issue.
            if (issue) begin
                lower_a_residue_reg <= lower_a_residue;
                lower_b_residue_reg <= lower_b_residue;
            end

            ar_reg <= ar_wire;
            br_reg <= br_wire;

            small_product_reg <= ar_reg * br_reg;

            expected_pipe[0] <= expected_wire;

            for (i = 1; i < 4; i = i + 1)
                expected_pipe[i] <= expected_pipe[i-1];


            // Observed partial-product residues.

            late_valid <= m_res1_vld;

            if (m_res1_vld)
                part1_residue <= part1_wire;

            if (late_valid)
                part2_residue <= part2_wire;


            // Issue-to-check alignment.

            valid_pipe <= {valid_pipe[5:0], issue};

            checked <= 0;

            if (valid_pipe[6]) begin

                checked <= 1;
                checks <= checks + 1;

                if (observed != expected_pipe[3])
                    alarm <= 1;

            end

        end

    end

endmodule
