// B4  mul2c : 2-cycle (W/2+1)-bit multiplier
//
// Paper : Alg. 8, Fig. 5, Eq. 20, Eq. 22-23, Table IV, Table V
// Spec  : FLALM_SPEC 6.2; A16 (Merge1 t5 = (t4,t1), CSA operand t5[W+1:W/4])
// Golden: model/datapath.py mul2c_stage1() / mul2c_stage2()
//
// cycle-1 : four (W/4+1)-bit multipliers mi1 x mi2 -> t1..t4 registers (en)
// cycle-2 : t5 = (t4,t1); (3W/4+2)-bit 3-2 CSA of t2, t3, t5[W+1:W/4];
//           (3W/4+2)-bit BKA; m_o = (S1, t5[W/4-1:0])      (combinational)
//
// mi1/mi2 are the Karatsuba input registers (outside this module).  A pair held
// in mi1/mi2 during cycle t is in t1..t4 during t+1 and on m_o during t+1, so
// the destination register (r1/r2/r3) captures it at the end of t+1: two
// cycles after mi was loaded.  One new pair can enter every cycle.
module mul2c #(
    parameter W = 128
) (
    input            clk,
    input            en,     // mi1/mi2 hold a valid pair in this cycle
    input  [W/2:0]   mi1,
    input  [W/2:0]   mi2,
    output [W+1:0]   m_o
);
    localparam Q  = W / 4;
    localparam CW = 3 * W / 4 + 2;

    // ---------------- cycle-1 (Alg. 8 line 2) ----------------
    wire [Q-1:0] mi10 = mi1[Q-1:0];
    wire [Q:0]   mi11 = mi1[W/2:Q];
    wire [Q-1:0] mi20 = mi2[Q-1:0];
    wire [Q:0]   mi21 = mi2[W/2:Q];

    wire [2*Q-1:0] p1;
    wire [2*Q:0]   p2;
    wire [2*Q:0]   p3;
    wire [2*Q+1:0] p4;
    mulq #(.AW(Q),   .BW(Q))   u_m1 (.a(mi10), .b(mi20), .p(p1));
    mulq #(.AW(Q+1), .BW(Q))   u_m2 (.a(mi11), .b(mi20), .p(p2));
    mulq #(.AW(Q),   .BW(Q+1)) u_m3 (.a(mi10), .b(mi21), .p(p3));
    mulq #(.AW(Q+1), .BW(Q+1)) u_m4 (.a(mi11), .b(mi21), .p(p4));

    reg [W/2-1:0] t1;       // mi10 * mi20
    reg [W/2:0]   t2;       // mi11 * mi20
    reg [W/2:0]   t3;       // mi10 * mi21
    reg [W/2+1:0] t4;       // mi11 * mi21
    always @(posedge clk) begin
        if (en) begin
            t1 <= p1;
            t2 <= p2;
            t3 <= p3;
            t4 <= p4;
        end
    end

    // ---------------- cycle-2 (Alg. 8 lines 3, 5-7) ----------------
    wire [W+1:0] t5 = {t4, t1};                         // Merge1

    wire [CW-1:0] s0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [CW-1:0] c0;                                   // C0 MSB dropped
    /* verilator lint_on UNUSEDSIGNAL */
    csa32 #(.WIDTH(CW)) u_csa (
        .a ({{(CW-W/2-1){1'b0}}, t2}),
        .b ({{(CW-W/2-1){1'b0}}, t3}),
        .c (t5[W+1:Q]),
        .s (s0),
        .cy(c0)
    );

    // (C0,1'b0): the C0 MSB and the BKA carry-out are zero because m_o < 2^(W+2)
    wire [CW-1:0] s1;
    /* verilator lint_off UNUSEDSIGNAL */
    wire          s1_cout;
    /* verilator lint_on UNUSEDSIGNAL */
    bka #(.WIDTH(CW)) u_bka (
        .x   ({c0[CW-2:0], 1'b0}),
        .y   (s0),
        .cin (1'b0),
        .s   (s1),
        .cout(s1_cout)
    );

    assign m_o = {s1, t5[Q-1:0]};                       // Merge2
endmodule
