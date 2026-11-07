// B11 flalm_core : FLALM without the RAM (Fig. 9 minus the DP-RAM; the measured core)
//
// Paper : Fig. 9 (FSM, PE, RAM ports a1/a2/o_D1/o_D2, d_to_RAM, len, SMM_en, M'),
//         Sec. IV-C (q[i] and S/SM words stored in the RAM, final subtraction, z_sel),
//         Eq. 26, Eq. 31, Table VII
// Spec  : FLALM_SPEC 7, 8, 9.1; A5, A6, A7, A8, A25-A27, A34, A37, A38
// Golden: model/cycle_model.py CycleSim (RAM ports a1/we/d/a2 and read data every
//         cycle, write sources, borrow, z_sel, done, F = 3S+6)
//
// Integration only; the verified blocks are instantiated unchanged:
//   ds_fsm    (B8)  schedule, DS2PE, logical RAM requests (region, index), write intents
//   pe_v2     (B7)  PE Version 2 (+ Fig. 9 operand MUX-1/MUX-2)
//   final_red (B9)  W-bit subtractor, borrow, z_sel
// plus the two pieces of glue that Fig. 9 draws between them:
//   * address map (A7): logical (region, index) -> BASE + index,
//       X_BASE = 0, Y_BASE = NW, M_BASE = 2NW, Q_BASE = 3NW (depth 4NW, Eq. 31).
//       Port A (a1) carries the write address when wr_en, else the operand-a read
//       (X or q); the DPRA (a2) carries the operand-b read (Y or M) or, in an SM
//       cycle, M[idx] for the subtraction.  For NW = 2^k the map is pure wiring
//       ({region, index}).
//   * d_to_RAM mux (Fig. 8/9, A27): wr_src 0 q[i] reg, 1 rb1[W-1:0], 2 rb2[W-1:0],
//       3 d_access, 4 rb1[2W-1:W]; SM words pass through final_red's subtractor.
// No register is added: RAM reads are combinational (non-registered DP-RAM, A9) and
// every write happens in the cycle ds_fsm requests it, so CYCLES = F = 3S+6.
// Idle / unused cycles: ram_we = 0; addresses are don't care (they follow the
// controller's idle request X[0] / M[0]).
// Verilog-2001 form: non-ANSI port list so that the port widths
// follow the localparams they use (no forward reference); $clog2 -> clog2.
module flalm_core #(
    parameter W  = 128,
    parameter NW = 8                        // NMAX / W: words per region
) (
    clk, rst, start, len, smm_en, mp, busy, done, z_sel, ram_a1, ram_we, ram_d, ram_a2,
    ram_o1, ram_o2, security_fault_out
);
    // Verilog-2001 form: constant function equal to the IEEE
    // 1364-2005 system function $clog2 (ceil(log2(value)); 0 for value <= 1).
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clog2 = 0; v > 0; clog2 = clog2 + 1)
                v = v >> 1;
        end
    endfunction
    localparam IW    = (NW > 1) ? clog2(NW) : 1;
    localparam KW    = IW + 1;
    localparam DEPTH = 4 * NW;
    localparam AW    = clog2(DEPTH);
    input              clk;
    input              rst;                 // synchronous, control state only (A25)
    input              start;               // sampled when idle (cycle 0, A5, A33)
    input  [KW-1:0]    len;                 // n; stable start..done (A26)
    input              smm_en;              // stable start..done (A26)
    input  [W-1:0]     mp;                  // M'_0; stable start..done (A26)
    output             busy;                // cycles 1..F
    output             done;                // level: set at the end of F, cleared by start
    output             z_sel;
    output             security_fault_out;               // 1: Z in the Y region (Z - M), 0: X region
    // DP-RAM (B10) ports
    output [AW-1:0]    ram_a1;              // port A address (write / o_D1 read)
    output             ram_we;
    output [W-1:0]     ram_d;
    output [AW-1:0]    ram_a2;              // DPRA address (o_D2 read)
    input  [W-1:0]     ram_o1;
    input  [W-1:0]     ram_o2;
    localparam WT    = 2 * W + 8;
    /* verilator lint_off WIDTHTRUNC */
    localparam [AW-1:0] X_BASE = 0;
    localparam [AW-1:0] Y_BASE = NW;
    localparam [AW-1:0] M_BASE = 2 * NW;
    localparam [AW-1:0] Q_BASE = 3 * NW;
    /* verilator lint_on WIDTHTRUNC */

    // ---------------- controller (B8) ----------------
    wire          pe_start, issue, access_en, q_cal, sche_sel, offdiag;
    wire          rb1_load, rb2_load, rb1_set0, rb2_set0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [1:0]    op_kind;                  // operation identity: trace only
    wire [KW-1:0] op_k;
    wire [IW-1:0] op_i, op_j;
    /* verilator lint_on UNUSEDSIGNAL */
    wire          rd1_en, rd1_q, rd2_en, rd2_m, wr_en, wr_fin;
    wire [IW-1:0] rd1_idx, rd2_idx, wr_idx;
    wire [1:0]    wr_rgn;
    wire [2:0]    wr_src;

    ds_fsm #(.NW(NW)) u_fsm (
        .clk(clk), .rst(rst), .start(start), .len(len), .smm_en(smm_en),
        .busy(busy), .done(done), .pe_start(pe_start),
        .issue(issue), .access_en(access_en), .q_cal(q_cal), .sche_sel(sche_sel),
        .offdiag(offdiag), .rb1_load(rb1_load), .rb2_load(rb2_load),
        .rb1_set0(rb1_set0), .rb2_set0(rb2_set0),
        .op_kind(op_kind), .op_k(op_k), .op_i(op_i), .op_j(op_j),
        .rd1_en(rd1_en), .rd1_q(rd1_q), .rd1_idx(rd1_idx),
        .rd2_en(rd2_en), .rd2_m(rd2_m), .rd2_idx(rd2_idx),
        .wr_en(wr_en), .wr_rgn(wr_rgn), .wr_idx(wr_idx), .wr_src(wr_src), .wr_fin(wr_fin));

    // ---------------- PE (B7) ----------------
    wire [W-1:0]  d_access, q_i;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WT-1:0] rb1, rb2;                 // rb2[2W+7:W]: not a RAM source
    /* verilator lint_on UNUSEDSIGNAL */
    pe_v2 #(.W(W)) u_pe (
        .clk(clk), .rst(rst), .start(pe_start), .issue(issue), .access_en(access_en),
        .q_cal(q_cal), .sche_sel(sche_sel), .smm_en(smm_en), .offdiag(offdiag),
        .rb1_load(rb1_load), .rb2_load(rb2_load), .rb1_set0(rb1_set0), .rb2_set0(rb2_set0),
        .o_d1(ram_o1), .o_d2(ram_o2), .mp(mp),
        .d_access(d_access), .rb1(rb1), .rb2(rb2), .q_i(q_i),
        .security_fault_out(security_fault_out));

    // ---------------- address map (A7) ----------------
    wire [AW-1:0] wr_base  = (wr_rgn == 2'd2) ? Q_BASE : (wr_rgn == 2'd1) ? Y_BASE : X_BASE;
    wire [AW-1:0] rd1_base = rd1_q ? Q_BASE : X_BASE;
    wire [AW-1:0] rd2_base = rd2_m ? M_BASE : Y_BASE;
    assign ram_a1 = wr_en ? (wr_base + {{(AW-IW){1'b0}}, wr_idx})
                          : (rd1_base + {{(AW-IW){1'b0}}, rd1_idx});
    assign ram_a2 = rd2_base + {{(AW-IW){1'b0}}, rd2_idx};
    assign ram_we = wr_en;

    // ---------------- d_to_RAM source mux (A27) ----------------
    reg [W-1:0] src;
    always @* begin
        case (wr_src)
            3'd0:    src = q_i;
            3'd1:    src = rb1[W-1:0];
            3'd2:    src = rb2[W-1:0];
            3'd3:    src = d_access;
            default: src = rb1[2*W-1:W];
        endcase
    end

    // ---------------- final subtraction / z_sel (B9) ----------------
    /* verilator lint_off UNUSEDSIGNAL */
    wire borrow;                            // observed by the testbenches
    /* verilator lint_on UNUSEDSIGNAL */
    final_red #(.W(W)) u_fin (
        .clk(clk), .rst(rst), .start(pe_start), .sm_we(wr_en & (wr_rgn == 2'd1)),
        .fin(wr_fin), .src(src), .o2(ram_o2), .t_top(rb1[2*W]),
        .ram_d(ram_d), .borrow(borrow), .z_sel(z_sel));

    // synthesis translate_off
    always @(posedge clk) begin
        if (!rst) begin
            if (wr_fin && rb1[WT-1:2*W+1] != 0)
                $display("ERROR flalm_core: rb1[2W+7:2W+1] != 0 at the final word (Z >= 2M) (t=%0t)",
                         $time);
            if (wr_en && rd1_en)
                $display("ERROR flalm_core: port A read and write in one cycle (t=%0t)", $time);
            if (wr_en && rd2_en && issue)
                $display("ERROR flalm_core: DPRA operand read in a write cycle (t=%0t)", $time);
            if (wr_en && wr_rgn == 2'd1 && !(rd2_en && rd2_m && rd2_idx == wr_idx))
                $display("ERROR flalm_core: SM word without its M read (t=%0t)", $time);
        end
    end
    // synthesis translate_on
endmodule
