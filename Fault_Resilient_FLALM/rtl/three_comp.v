// B7a three_comp : three-time compression (one iterative compressor reused
//                  three times) with the Table VI input MUXes and rc1/rc2
//
// Paper : Alg. 7, Eq. 13-16, Fig. 8, Table VI, Table IV (Comp-1/2/3 at c+5..c+7)
// Spec  : FLALM_SPEC 6.5; A11 (q_cal forces in3 = 0); A12 (shift per operation);
//         A25 (sync reset on control state only)
// Golden: model/datapath.py comp1_inputs(), comp1_regs(), iter_comp(), pe_op()
//
// Scope: the compressor path only.  rb1/rb2, q[i], d_access, the rb1/rb2
// selection (sche-sel, rbX-load) and all rb writes belong to the PE (pe_v2);
// here R_PRes (rb_sel) and O_PRes[2W+7:W] (rb_oth_h) arrive already selected.
//
//   Comp-1 (c1_go)   : in1 = oload ? rb_oth_h : 0            (MUX-3)
//                      in2 = shift ? M_Res1<<1 : M_Res1      (MUX-1)
//                      in3 = q_cal ? 0 : rb_sel              (MUX-2, A11)
//                      end: rc1 <- (out2, out1[3W/4+3:W/2]), rc2 <- (out3, (W/4+4)'b0)
//                      PE_Res[W/2-1:0]      = out1[W/2-1:0]
//   Comp-2 (+1 cycle): in1 = shift ? M_Res2<<1 : M_Res2 ; in2 = rc2 ; in3 = rc1
//                      end: rc1 <- out2, rc2 <- out3
//                      PE_Res[5W/4+3:W/2]   = out1
//   Comp-3 (+2 cycle): in1 = 0 ; in2 = rc2 ; in3 = rc1
//                      PE_Res[2W+7:5W/4+4]  = out1 (out2 = out3 = 0)
//
// shift, oload, q_cal, m_res1, rb_sel, rb_oth_h are sampled in the Comp-1 cycle;
// m_res2 in the Comp-2 cycle (the Karatsuba r2 register at c+6).
module three_comp #(
    parameter W = 128
) (
    input                clk,
    input                rst,        // synchronous, control state only
    input                c1_go,      // Comp-1 of a valid operation in this cycle
    input                shift,      // SMM doubling of this operation
    input                oload,      // rbX-load: add O_PRes >> W
    input                q_cal,      // Q(k) operation: no R_PRes
    input  [2*W-1:0]     m_res1,
    input  [W:0]         m_res2,
    input  [2*W+7:0]     rb_sel,     // R_PRes
    input  [W+7:0]       rb_oth_h,   // O_PRes[2W+7:W]
    output               comp1,      // Comp-STATE
    output               comp2,
    output               comp3,
    output [3*W/4+3:0]   out1,
    output [5*W/4+3:0]   out2,
    output [5*W/4+3:0]   out3
);
    localparam WT  = 2 * W + 8;
    localparam L   = 3 * W / 4 + 4;
    localparam RCW = 3 * W / 2 + 8;
    localparam LO  = W / 4 + 4;      // = L - W/2 = RCW - H

    // Comp-STATE sequencing: Comp-1 -> Comp-2 -> Comp-3 on consecutive cycles
    reg c2_r, c3_r;
    always @(posedge clk) begin
        if (rst) begin
            c2_r <= 1'b0;
            c3_r <= 1'b0;
        end else begin
            c2_r <= c1_go;
            c3_r <= c2_r;
        end
    end
    assign comp1 = c1_go;
    assign comp2 = c2_r;
    assign comp3 = c3_r;

    // the SMM doubling of M_Res2 is applied one cycle after Comp-1
    reg shift2;
    always @(posedge clk) begin
        if (c1_go) shift2 <= shift;
    end

    reg [RCW-1:0] rc1, rc2;

    // ---------------- Table VI input MUXes ----------------
    wire [W+7:0]  m2_x = shift2 ? {6'b0, m_res2, 1'b0} : {7'b0, m_res2};
    wire [WT-1:0] m1_x = shift  ? {7'b0, m_res1, 1'b0} : {8'b0, m_res1};

    wire [W+7:0]  in1 = comp1 ? (oload ? rb_oth_h : {(W+8){1'b0}}) :
                        comp2 ? m2_x : {(W+8){1'b0}};                       // MUX-3
    wire [WT-1:0] in2 = comp1 ? m1_x : {{(WT-RCW){1'b0}}, rc2};             // MUX-1
    wire [WT-1:0] in3 = comp1 ? (q_cal ? {WT{1'b0}} : rb_sel) :
                                {{(WT-RCW){1'b0}}, rc1};                    // MUX-2

    iter_comp #(.W(W)) u_ic (
        .in1 (in1),
        .in2 (in2),
        .in3 (in3),
        .out1(out1),
        .out2(out2),
        .out3(out3)
    );

    always @(posedge clk) begin
        if (comp1) begin
            rc1 <= {out2, out1[L-1:W/2]};
            rc2 <= {out3, {LO{1'b0}}};
        end else if (comp2) begin
            rc1 <= {{LO{1'b0}}, out2};
            rc2 <= {{LO{1'b0}}, out3};
        end
    end

    // synthesis translate_off
    always @(posedge clk) begin
        if (!rst && ((comp1 & comp2) | (comp1 & comp3) | (comp2 & comp3)))
            $display("ERROR three_comp: two compression stages in one cycle (t=%0t)", $time);
    end
    // synthesis translate_on
endmodule
