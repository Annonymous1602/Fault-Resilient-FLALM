// B6  iter_comp : iterative compressor
//
// Paper : Alg. 6, Fig. 4, Fig. 7, Eq. 19
// Spec  : FLALM_SPEC 6.4; A16 (carry shift applied once)
// Golden: model/datapath.py iter_comp()
//
// in1 is (W+8)-bit (zero-padded to 2W+8), in2/in3 are (2W+8)-bit.
// L = 3W/4+4, H = 5W/4+4.  Purely combinational.
//   1: (C0,1'b0) + S0 = 3-2 CSA(in1, in2, in3)          (2W+8 bits)
//   2: C0 = C0 << 1                                       (MSB dropped)
//   3: (C1,1'b0) + S1 = 2-2 CSA(C0[2W+7:L], S0[2W+7:L])  (H bits)
//   4: (C2, S2) = BKA(C0[L-1:0], S0[L-1:0])              (L bits)
//   6: out1 = S2 ; 7: out2 = S1 ; 8: out3 = (C1[H-2:0], C2)
// out1 + (out2 + out3) * 2^L == in1 + in2 + in3 (mod 2^(2W+8)) whenever the
// dropped C0/C1 MSBs are zero (guaranteed by the 2W+8-bit headroom).
module iter_comp #(
    parameter W = 128
) (
    input  [W+7:0]       in1,
    input  [2*W+7:0]     in2,
    input  [2*W+7:0]     in3,
    output [3*W/4+3:0]   out1,
    output [5*W/4+3:0]   out2,
    output [5*W/4+3:0]   out3
);
    localparam WT = 2 * W + 8;
    localparam L  = 3 * W / 4 + 4;
    localparam H  = 5 * W / 4 + 4;

    wire [WT-1:0] s0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WT-1:0] c0;          // C0 MSB dropped (line 2)
    /* verilator lint_on UNUSEDSIGNAL */
    csa32 #(.WIDTH(WT)) u_csa32 (
        .a ({{W{1'b0}}, in1}),
        .b (in2),
        .c (in3),
        .s (s0),
        .cy(c0)
    );
    wire [WT-1:0] c0s = {c0[WT-2:0], 1'b0};

    wire [H-1:0] s1;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [H-1:0] c1;           // C1 MSB dropped (line 8)
    /* verilator lint_on UNUSEDSIGNAL */
    csa22 #(.WIDTH(H)) u_csa22 (
        .a (c0s[WT-1:L]),
        .b (s0[WT-1:L]),
        .s (s1),
        .cy(c1)
    );

    wire [L-1:0] s2;
    wire         c2;
    bka #(.WIDTH(L)) u_bka (
        .x   (c0s[L-1:0]),
        .y   (s0[L-1:0]),
        .cin (1'b0),
        .s   (s2),
        .cout(c2)
    );

    assign out1 = s2;
    assign out2 = s1;
    assign out3 = {c1[H-2:0], c2};
endmodule
