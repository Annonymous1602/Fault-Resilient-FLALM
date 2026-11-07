// B9  final_red : word-serial final subtraction Z - M, borrow chain, z_sel
//
// Paper : Alg. 4 lines 31-32 (Z = T >> nW; Z >= M ? Z - M : Z), Eq. 26, Sec. IV-C
//         (W-bit BKA subtractor, S/SM stored in RAM, z_sel selects the result)
// Spec  : FLALM_SPEC 7 (d_to_RAM) and 8 (micro-schedule); A6, A7, A25, A27, A38
// Golden: model/cycle_model.py (SM event: diff = val - o2 - borrow, borrow <- b_out,
//         z_sel <- rb1[2W] | ~b_out at the final SM word; borrow cleared at start)
//
// Purely a datapath slice: the controller (ds_fsm) decides when an SM word is
// written (sm_we, RAM region Y) and which d_to_RAM source is the minuend (src).
//   sm_we = 0 : ram_d = src                  (q word, S word)
//   sm_we = 1 : ram_d = src - m_r - borrow   (SM word; m_r = M[idx], the DPRA read
//                                             data o2 of the previous cycle, A50)
//               end of cycle: borrow <- borrow-out
//   fin   = 1 : (last SM word, cycle F) end of cycle: z_sel <- T[2n] | ~borrow-out
//               T[2n] = rb1[2W] (carry above the top result word; Z < 2M)
// z_sel = 1: the result is Z - M (Y region, SM words); 0: Z (X region, S words).
// "Z >= M" (not ">"): equality gives no borrow, so Z = M selects Z - M = 0.
// The borrow is cleared when start is sampled (and by rst, A25); z_sel keeps its
// value until the next final word so the host can read it after done.
module final_red #(
    parameter W = 128
) (
    input              clk,
    input              rst,        // synchronous, control state only (A25)
    input              start,      // start sampled (cycle 0): borrow <- 0
    input              sm_we,      // SM word written in this cycle
    input              fin,        // last SM word (cycle F)
    input  [W-1:0]     src,        // d_to_RAM source (minuend of an SM word)
    input  [W-1:0]     o2,         // RAM DPRA read data = M[idx] in the cycle before
                                   // an SM cycle (and in the SM cycle itself)
    input              t_top,      // rb1[2W] = T[2n]
    output [W-1:0]     ram_d,
    output reg         borrow,
    output reg         z_sel
);
    // M register (A50): the subtrahend is registered one cycle early.  ds_fsm
    // drives the DPRA with M_BASE + idx already in the cycle before every SM word and
    // the M region is never written (proven for every SM word, A50), so
    // m_r = M[idx] in every SM cycle.  Captured every cycle (no enable): m_r is only
    // observed when sm_we = 1.
    reg  [W-1:0] m_r;
    always @(posedge clk)
        m_r <= o2;

    // W-bit Brent-Kung subtractor: src + ~m_r + ~borrow (Eq. 26)
    wire [W-1:0] diff;
    wire         cout;
    bka #(.WIDTH(W)) u_sub (.x(src), .y(~m_r), .cin(~borrow), .s(diff), .cout(cout));
    wire b_out = ~cout;

    assign ram_d = sm_we ? diff : src;

    always @(posedge clk) begin
        if (rst | start)
            borrow <= 1'b0;
        else if (sm_we)
            borrow <= b_out;
    end
    always @(posedge clk) begin
        if (fin)
            z_sel <= t_top | ~b_out;
    end
endmodule
