// B12 flalm : FLALM top level (Fig. 9) = flalm_core + W-bit non-registered DP-RAM
//
// Paper : Fig. 9, Sec. IV-C, Sec. V-B, Table X (FLALM with RAM)
// Spec  : FLALM_SPEC 9.2; A4, A7, A8, A9, A37
//
// The measured architecture: no host load/readback logic (that lives only in the
// simulation testbench, A8).  Operands are placed in the RAM and the
// result is read from it outside this module (backdoor in simulation).
// Verilog-2001 form: non-ANSI port list so that the port widths
// follow the localparams they use (no forward reference); $clog2 -> clog2.
module flalm #(
    parameter W  = 128,
    parameter NW = 8                        // NMAX / W; RAM depth 4NW (Eq. 31)
) (
    clk, rst, start, len, smm_en, mp, busy, done, z_sel, security_fault_out
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
    input              rst;
    input              start;
    input  [KW-1:0]    len;
    input              smm_en;
    input  [W-1:0]     mp;
    output             busy;
    output             done;
    output             z_sel;
    output             security_fault_out;

    wire [AW-1:0] ram_a1, ram_a2;
    wire          ram_we;
    wire [W-1:0]  ram_d, ram_o1, ram_o2;

    flalm_core #(.W(W), .NW(NW)) u_core (
        .clk(clk), .rst(rst), .start(start), .len(len), .smm_en(smm_en), .mp(mp),
        .busy(busy), .done(done), .z_sel(z_sel),
        .security_fault_out(security_fault_out),
        .ram_a1(ram_a1), .ram_we(ram_we), .ram_d(ram_d), .ram_a2(ram_a2),
        .ram_o1(ram_o1), .ram_o2(ram_o2));

    dpram #(.W(W), .DEPTH(DEPTH)) u_ram (
        .clk(clk), .we(ram_we), .a(ram_a1), .d(ram_d), .dpra(ram_a2),
        .spo(ram_o1), .dpo(ram_o2));
endmodule
