// B8  ds_fsm : Dual-Schedule FSM (control plane only)
//
// Paper : Alg. 4 (+ Fig. 1), Sec. III-A/B (Insert / Fixed / Inserted / q[i] / q[i]M[0]
//         regions, NUM-Inserted = 2, Schedule-1 = R-k with k%2 = 0, Schedule-2 = R-k
//         with k%2 = 1), Fig. 2, Table I, Table VII (DS2PE timing), Eq. 11/12,
//         Fig. 9 (len, SMM_en, DS2PE), Sec. IV-C (q[i] and S/SM RAM writes)
// Spec  : FLALM_SPEC 3 (slot sequence), 4 (cycle numbering), 5 (per-slot timing and
//         operand selection), 7 (RAM map, port discipline), 8 (final-reduction write
//         schedule); A1, A5, A6, A7, A10, A13-A15, A21, A22, A25, A26, A29, A32, A33
// Golden: model/schedule.py build_schedule() (slot list), model/cycle_model.py
//         (control trace, RAM write events)
//
// The FSM generates the schedule algorithmically for any legal len (4 <= n <= NW,
// n <= 127); nothing is tabulated.  One slot every 3 cycles; slot s has base cycle
// c = 3s-3 relative to the cycle in which start is sampled (cycle 0, A5).
//
//   for k = 0 .. n-1 (LOOP-1)                       slot types (st)
//     body(k): XY ops of R-k not yet issued        XY   (Alg. 4 order)
//              q[j]M[k-j], j = 0 .. k-1            QM   (last one carries O_PRes)
//     ins1   : next XY op of R-(k+1) or bubble     INS1
//     Q(k)   : q[k] = qr * M'_0                    Q
//     ins2   : next XY op of R-(k+1) or bubble     INS2
//     q[k]M[0]                                     QM0
//   for k = n .. 2n-2 (LOOP-2)
//     body(k): XY ops not yet issued, then q[j]M[k-j], j = k-n+1 .. n-1 (last: O_PRes)
//
// A single XY iterator (kx, jx, sx, xe) walks the XY operations of one group in
// Alg. 4 order: j = jlo .. floor(kx/2); diagonal X[j]Y[j]; off-diagonal GMM
// X[j]Y[kx-j] then X[kx-j]Y[j] (sx), SMM 2X[j]Y[kx-j].  It points at R-k during the
// body of R-k and at R-(k+1) during ins1/ins2, so an insert slot takes the next
// XY op of R-(k+1) and the body of R-(k+1) resumes after the inserted ones.  An insert
// slot finds the iterator exhausted only in SMM at k = 0 (R-1 has the single op
// 2X[0]Y[1]): that ins2 slot is the SMM bubble (slot 4).
//
// Per-slot events travel in a slot-age pipeline (a1 = previous slot, a2, a3), shifted
// at every slot boundary.  With ph = cycle within the slot, an event d cycles after
// the base of a slot of age a happens when 3a + ph = d:
//   c+5 (a1, ph2): rbX_load                 c+6 (a2, ph0): rbX_set0, tail S[n-2]
//   c+7 (a2, ph1): q write / S write / tail SM[n-2]
//   c+8 (a2, ph2): SM write / tail S[n-1]    c+9 (a3, ph0): tail SM[n-1], done
// After the last slot the FSM drains (bubbles) until the c+9 event: F = 3S+6.
//
// Outputs are logical: operation identity and RAM requests as (region, index).  The
// RAM stage maps them to addresses (X_BASE + idx, ...); the final-reduction stage
// uses wr_src / region Y (subtract o_d2 = M[idx] and the borrow) and wr_fin.
// Verilog-2001 form: non-ANSI port list so that the port widths
// follow the localparams they use (no forward reference); $clog2 -> clog2.
module ds_fsm #(
    parameter NW = 8                        // max words per operand (NMAX / W)
) (
    clk, rst, start, len, smm_en, busy, done, pe_start, issue, access_en, q_cal,
    sche_sel, offdiag, rb1_load, rb2_load, rb1_set0, rb2_set0, op_kind, op_k, op_i,
    op_j, rd1_en, rd1_q, rd1_idx, rd2_en, rd2_m, rd2_idx, wr_en, wr_rgn, wr_idx, wr_src,
    wr_fin
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
    localparam IW = (NW > 1) ? clog2(NW) : 1;  // word index
    localparam KW = IW + 1;                     // group index k <= 2n-2, len (n <= NW)
    input               clk;
    input               rst;                // synchronous, control state only (A25)
    input               start;              // sampled when idle (A5); ignored when busy (A33)
    input  [KW-1:0]     len;                // n = N / W, held stable start..done (A26)
    input               smm_en;             // held stable start..done (A26)
    output reg          busy;               // cycles 1 .. F of a computation
    output reg          done;               // set at the end of F, cleared by start
    output              pe_start;           // start accepted (cycle 0): PE clears rb1/rb2 (A29)
    // DS2PE (Fig. 9, Table VII) + A32 issue/offdiag
    output              issue;              // cycle c: an operation is issued
    output              access_en;          // cycle c: a <- d_access (Q, q[k]M[0])
    output              q_cal;              // c..c+2: Q(k)
    output              sche_sel;           // c..c+2: 0 = Schedule-1 (rb1), 1 = Schedule-2 (rb2)
    output              offdiag;            // c..c+2: X[i]Y[j], i != j (SMM x2, A12)
    output              rb1_load;           // c+5 of an O_PRes op, O_PRes = rb1_h
    output              rb2_load;           //                        O_PRes = rb2_h
    output              rb1_set0;           // c+6 of that op
    output              rb2_set0;
    // operation identity (valid with issue)
    output [1:0]        op_kind;            // 0 X[i]Y[j], 1 q[i]M[j], 2 Q(k) = qrM', 3 q[k]M[0]
    output [KW-1:0]     op_k;               // group R-k
    output [IW-1:0]     op_i;
    output [IW-1:0]     op_j;
    // logical RAM read requests (combinational, in the cycle of use)
    output              rd1_en;             // port A (o_D1): operand a
    output              rd1_q;              //   0: X[rd1_idx], 1: q[rd1_idx]
    output [IW-1:0]     rd1_idx;
    output              rd2_en;             // DPRA (o_D2): operand b, or M word of an SM write
    output              rd2_m;              //   0: Y[rd2_idx], 1: M[rd2_idx]
    output [IW-1:0]     rd2_idx;
    // logical RAM write request (port A)
    output              wr_en;
    output [1:0]        wr_rgn;             // 0: X (S word), 1: Y (SM word = src - M[idx] - borrow), 2: q
    output [IW-1:0]     wr_idx;
    output [2:0]        wr_src;             // d_to_RAM: 0 q[i] reg, 1 rb1_lo, 2 rb2_lo, 3 d_access, 4 rb1[2W-1:W]
    output              wr_fin;             // last SM word: z_sel and done (cycle F)

    localparam [2:0] S_XY = 3'd0, S_QM = 3'd1, S_INS1 = 3'd2, S_Q = 3'd3, S_INS2 = 3'd4,
                     S_QM0 = 3'd5, S_DRAIN = 3'd6;
    localparam [2:0] SRC_Q = 3'd0, SRC_RB1L = 3'd1, SRC_D = 3'd3, SRC_RB1H = 3'd4;
    localparam [1:0] RG_X = 2'd0, RG_Y = 2'd1, RG_Q = 2'd2;
    localparam [KW-1:0] K2 = 2;
    localparam [IW-1:0] I2 = 2;

    // ---------------- state ----------------
    reg [1:0]    ph;                 // cycle within the slot (0 = base, issue)
    reg [2:0]    st;                 // slot type of the current slot
    reg [KW-1:0] k;                  // current group R-k
    reg [IW-1:0] jq;                 // q[jq]M[k-jq] iterator
    reg [KW-1:0] kx;                 // XY iterator: group,
    reg [IW-1:0] jx;                 //   j,
    reg          sx;                 //   second (mirrored) GMM op of the pair,
    reg          xe;                 //   exhausted
    // slot-age pipeline (per-slot events)
    reg          a1_ol, a1_or, a1_qw, a1_sw, a1_tl, a1_rs;
    reg [IW-1:0] a1_ix;
    reg          a2_ol, a2_or, a2_qw, a2_sw, a2_tl, a2_rs;
    reg [IW-1:0] a2_ix;
    reg          a3_tl;

    // ---------------- group bounds (n = len) ----------------
    wire [KW-1:0] n     = len;
    wire          loop2 = (k >= n);
    wire [KW-1:0] kmax  = n + n - K2;                  // 2n-2
    wire          klast = (k == kmax);
    // q[j]M[k-j]: j = jlo(k) .. jmax(k).  Values that are only used truncated to IW
    // bits (all < n <= NW where they are used) keep their KW-bit form.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [KW-1:0] jlo_k  = loop2 ? (k - n + 1'b1) : {KW{1'b0}};
    wire [KW-1:0] jmax_k = loop2 ? (n - 1'b1) : (k - 1'b1);
    // XY iterator start of group k+1
    wire [KW-1:0] k1      = k + 1'b1;
    wire [KW-1:0] jlo_k1  = (k1 >= n) ? (k1 - n + 1'b1) : {KW{1'b0}};
    wire [KW-1:0] k2      = k + K2;
    wire [KW-1:0] jlo_k2  = (k2 >= n) ? (k2 - n + 1'b1) : {KW{1'b0}};
    wire [KW-1:0] kmn     = k - n;                      // S / SM word index of R-k
    /* verilator lint_on UNUSEDSIGNAL */

    // ---------------- XY iterator decode ----------------
    wire [KW-1:0] jx2    = {jx, 1'b0};
    wire          xdiag  = (jx2 == kx);
    wire          xlast  = xdiag | ((jx2 + 1'b1 == kx) & (smm_en | sx));   // last XY op of kx
    /* verilator lint_off UNUSEDSIGNAL */
    wire [KW-1:0] kxmj   = kx - {1'b0, jx};                // < n where used
    /* verilator lint_on UNUSEDSIGNAL */
    wire [IW-1:0] x_i    = sx ? kxmj[IW-1:0] : jx;
    wire [IW-1:0] x_j    = sx ? jx : kxmj[IW-1:0];

    // ---------------- current slot decode ----------------
    wire is_xy  = (st == S_XY) | (((st == S_INS1) | (st == S_INS2)) & ~xe);
    wire is_qm  = (st == S_QM);
    wire is_q   = (st == S_Q);
    wire is_qm0 = (st == S_QM0);
    wire valid  = is_xy | is_qm | is_q | is_qm0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [KW-1:0] kmj   = k - {1'b0, jq};                  // < n in S_QM
    /* verilator lint_on UNUSEDSIGNAL */
    wire          qlast = ({1'b0, jq} == jmax_k);        // last body op of R-k: O_PRes
    wire          oload = is_qm & qlast;                 // (k >= 1 always holds in S_QM)

    wire          act   = busy | pe_start;               // a computation is running
    wire          slot  = act & valid;                   // current slot holds an operation
    assign pe_start  = start & ~busy;
    assign issue     = slot & (ph == 2'd0);
    assign access_en = issue & (is_q | is_qm0);
    assign q_cal     = slot & is_q;
    assign sche_sel  = slot & op_k[0];
    assign offdiag   = slot & is_xy & ~xdiag;

    assign op_kind = is_qm0 ? 2'd3 : is_q ? 2'd2 : is_qm ? 2'd1 : 2'd0;
    assign op_k    = is_xy ? kx : k;
    assign op_i    = is_xy ? x_i : is_qm ? jq : k[IW-1:0];
    assign op_j    = is_xy ? x_j : is_qm ? kmj[IW-1:0] : is_q ? k[IW-1:0] : {IW{1'b0}};

    // ---------------- events from the slot-age pipeline ----------------
    // (c+5 of the a1 slot = ev5 = busy & ph 2: rbX_load, registered below, A51)
    wire ev6  = busy & (ph == 2'd0);                     // c+6 of the a2 slot / c+9 of a3
    wire ev7  = busy & (ph == 2'd1);
    wire ev8  = busy & (ph == 2'd2);
    assign rb1_set0 = ev6 & a2_ol & ~a2_or;
    assign rb2_set0 = ev6 & a2_ol &  a2_or;

    wire w_ts0 = ev6 & a2_tl;                            // X[n-2] <- d_access
    wire w_q   = ev7 & a2_qw;                            // q[k]   <- q[i] reg
    wire w_s   = ev7 & a2_sw;                            // X[k-n] <- rb_{k%2}[W-1:0]
    wire w_ts1 = ev7 & a2_tl;                            // Y[n-2] <- q[i] - M[n-2]
    wire w_sm  = ev8 & a2_sw;                            // Y[k-n] <- q[i] - M[k-n]
    wire w_ts2 = ev8 & a2_tl;                            // X[n-1] <- rb1[2W-1:W]
    wire w_ts3 = ev6 & a3_tl;                            // Y[n-1] <- rb1[2W-1:W] - M[n-1]
    wire [IW-1:0] n1 = n[IW-1:0] - 1'b1;
    wire [IW-1:0] n2 = n[IW-1:0] - I2;

    assign wr_en  = w_ts0 | w_q | w_s | w_ts1 | w_sm | w_ts2 | w_ts3;
    assign wr_rgn = w_q ? RG_Q : (w_ts1 | w_sm | w_ts3) ? RG_Y : RG_X;
    assign wr_idx = (w_q | w_s | w_sm) ? a2_ix : (w_ts0 | w_ts1) ? n2 : n1;
    assign wr_fin = w_ts3;

    // Registered strobes (A51): rb1_load / rb2_load (Table VII rbX-load, MUX-3 select) and
    // wr_src (d_to_RAM select) are registers loaded at the end of the previous cycle with
    // the value the combinational decode
    //   rb1_load = ev5 & a1_ol & ~a1_or,   rb2_load = ev5 & a1_ol & a1_or,
    //   wr_src   = w_s ? 1 + a2_rs : w_ts0 ? 3 : (w_ts2 | w_ts3) ? 4 : 0
    // has in the next cycle (proven equal to the decode in every cycle, A51).
    // nx_ph0/1/2: the next cycle is a busy cycle with ph = 0/1/2.  a1_* / a2_* do not
    // change into ph 1 or ph 2; into ph 0 (slot_end) a2 <- a1 and a3 <- a2.  A start from
    // idle leads to ph 1 with a1 = a2 = 0, and fin (a3_tl at ph 0) or rst to idle.
    wire nx_ph0 = ~rst & busy & (ph == 2'd2);
    wire nx_ph1 = ~rst & busy & (ph == 2'd0) & ~a3_tl;
    wire nx_ph2 = ~rst & busy & (ph == 2'd1);
    reg       rb1_load_r, rb2_load_r;
    reg [2:0] wr_src_r;
    always @(posedge clk) begin
        rb1_load_r <= nx_ph2 & a1_ol & ~a1_or;
        rb2_load_r <= nx_ph2 & a1_ol &  a1_or;
        wr_src_r   <= (nx_ph1 & a2_sw) ? (SRC_RB1L + {2'b0, a2_rs}) : (nx_ph0 & a1_tl) ? SRC_D
                    : ((nx_ph2 | nx_ph0) & a2_tl) ? SRC_RB1H : SRC_Q;
    end
    assign rb1_load = rb1_load_r;
    assign rb2_load = rb2_load_r;
    assign wr_src   = wr_src_r;

    wire rd_sm = w_ts1 | w_sm | w_ts3;                   // M word for the SM subtraction
    assign rd1_en  = issue & (is_xy | is_qm);
    assign rd1_q   = is_qm;
    assign rd1_idx = op_i;
    assign rd2_en  = (issue & (is_xy | is_qm | is_qm0)) | rd_sm;
    assign rd2_m   = ~(issue & is_xy);
    assign rd2_idx = issue ? op_j : wr_idx;

    // ---------------- sequencing ----------------
    wire slot_end = busy & (ph == 2'd2);
    wire fin      = w_ts3;

    // XY iterator step: next op of the same group, or exhausted
    task xy_step;
        begin
            if (xlast) begin
                xe <= 1'b1;
            end else if (~smm_en & ~xdiag & ~sx) begin
                sx <= 1'b1;
            end else begin
                jx <= jx + 1'b1;
                sx <= 1'b0;
            end
        end
    endtask
    // XY iterator to the first op of R-(k+1)
    task xy_next_group;
        begin
            kx <= k1;
            jx <= jlo_k1[IW-1:0];
            sx <= 1'b0;
            xe <= 1'b0;
        end
    endtask
    // body of R-(k+1); the iterator already points at R-(k+1)
    task enter_body;
        begin
            k <= k1;
            if (xe) begin                            // all its XY ops were inserted
                st <= S_QM;
                jq <= jlo_k1[IW-1:0];
                kx <= k2;                            // iterator -> R-(k+2)
                jx <= jlo_k2[IW-1:0];
                sx <= 1'b0;
                xe <= 1'b0;
            end else begin
                st <= S_XY;
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst | fin) begin
            busy <= 1'b0;
            done <= ~rst & fin;
            ph   <= 2'd0;
            st   <= S_XY;                            // slot 1 = X[0]Y[0] of R-0
            k    <= {KW{1'b0}};
            jq   <= {IW{1'b0}};
            kx   <= {KW{1'b0}};
            jx   <= {IW{1'b0}};
            sx   <= 1'b0;
            xe   <= 1'b0;
            {a1_ol, a1_or, a1_qw, a1_sw, a1_tl, a1_rs} <= 6'b0;
            {a2_ol, a2_or, a2_qw, a2_sw, a2_tl, a2_rs} <= 6'b0;
            a1_ix <= {IW{1'b0}};
            a2_ix <= {IW{1'b0}};
            a3_tl <= 1'b0;
        end else begin
            if (pe_start) begin
                busy <= 1'b1;
                done <= 1'b0;
            end
            if (act)
                ph <= (ph == 2'd2) ? 2'd0 : ph + 1'b1;
            if (slot_end) begin
                // ---- slot-age pipeline ----
                a1_ol <= slot & oload;
                a1_or <= ~k[0];                          // O_PRes = rb of R-(k-1)
                a1_qw <= slot & is_q;
                a1_sw <= slot & oload & loop2 & ~klast;  // LOOP-2 group end, k <= 2n-3
                a1_tl <= slot & oload & klast;           // last operation (R-(2n-2))
                a1_rs <= k[0];
                a1_ix <= is_q ? k[IW-1:0] : kmn[IW-1:0];
                {a2_ol, a2_or, a2_qw, a2_sw, a2_tl, a2_rs} <=
                    {a1_ol, a1_or, a1_qw, a1_sw, a1_tl, a1_rs};
                a2_ix <= a1_ix;
                a3_tl <= a2_tl;
                // ---- next slot ----
                case (st)
                    S_XY: begin
                        xy_step;
                        if (xlast) begin                 // XY part of R-k done
                            if (~klast) xy_next_group;
                            st <= (k == {KW{1'b0}}) ? S_INS1 : S_QM;
                            jq <= jlo_k[IW-1:0];
                        end
                    end
                    S_QM: begin
                        if (qlast) begin                 // body of R-k done
                            if (~loop2)     st <= S_INS1;
                            else if (klast) st <= S_DRAIN;
                            else            enter_body;
                        end else begin
                            jq <= jq + 1'b1;
                        end
                    end
                    S_INS1: begin
                        if (~xe) xy_step;
                        st <= S_Q;
                    end
                    S_Q:    st <= S_INS2;
                    S_INS2: begin
                        if (~xe) xy_step;
                        st <= S_QM0;
                    end
                    S_QM0:  enter_body;
                    default: ;                           // S_DRAIN: wait for the c+9 event
                endcase
            end
        end
    end

    // synthesis translate_off
    /* verilator lint_off WIDTHEXPAND */
    always @(posedge clk) begin
        if (!rst && pe_start && (len < 4 || len > NW || len > 127))
            $display("ERROR ds_fsm: len=%0d outside 4..min(NW=%0d,127) (A21)", len, NW);
    end
    /* verilator lint_on WIDTHEXPAND */
    // synthesis translate_on
endmodule
