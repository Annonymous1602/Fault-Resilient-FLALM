// B10 dpram : W-bit non-registered distributed dual-port RAM (simulation model and
//             inference template)
//
// Paper : Sec. IV-C, Eq. 31 (depth 4N/w), Eq. 32/33, Fig. 9 (RAM, d_to_RAM, a1/a2,
//         o_D1/o_D2); Sec. V-B: Distributed Memory Generator, w-bit Dual Port RAM,
//         "Non Registered"
// Spec  : FLALM_SPEC 7; A7 (address map), A9 (non-registered), A37 (port behaviour
//         and Vivado mapping)
// Golden: model/cycle_model.py (async read / sync write DP-RAM, port A: a1, we, d, o1;
//         DPRA: a2, o2)
//
// Port names follow the Xilinx Distributed Memory Generator (PG063) "Dual Port RAM"
// with non-registered inputs and outputs:
//   a    : port A address (write address and first read address, Fig. 9 a1)
//   d, we: write data / write enable, written at the rising edge of clk
//   spo  : mem[a],    combinational (Fig. 9 o_D1)
//   dpra : second read address (Fig. 9 a2)
//   dpo  : mem[dpra], combinational (Fig. 9 o_D2)
//
// Read-during-write: a write takes effect at the clock edge.  In the write cycle
// both outputs show the OLD word (also when a == dpra); from the next cycle they
// show the new word.  A register that samples spo/dpo at the edge of the write
// therefore captures the old word.  This is the behaviour of the DMG IP with
// non-registered outputs and of Vivado-inferred LUTRAM (RAM32X1D / RAM32M /
// RAM64M: synchronous write, asynchronous read) and is verified explicitly by
// tb/tb_dpram.v and in the integrated traces (tests/test_s5_flalm.py), not assumed.
//
// Vivado mapping: either this module as written (inferred,
// ram_style = "distributed") or a DMG IP instance with memory type "Dual Port RAM",
// depth DEPTH, data width W, input and output options "Non Registered", ports
// a/d/dpra/clk/we/spo/dpo connected one to one.  No reset, no initial contents.
// Verilog-2001 form: non-ANSI port list so that the port widths
// follow the localparams they use (no forward reference); $clog2 -> clog2.
module dpram #(
    parameter W     = 128,
    parameter DEPTH = 32
) (
    clk, we, a, d, dpra, spo, dpo
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
    localparam AW = (DEPTH > 1) ? clog2(DEPTH) : 1;
    input              clk;
    input              we;
    input  [AW-1:0]    a;
    input  [W-1:0]     d;
    input  [AW-1:0]    dpra;
    output [W-1:0]     spo;
    output [W-1:0]     dpo;

    (* ram_style = "distributed" *) reg [W-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) mem[a] <= d;
    end
    assign spo = mem[a];
    assign dpo = mem[dpra];

    // synthesis translate_off
    // (X checks are meaningful in 4-state simulators only; an undefined enable is
    // reported once the enable has been defined, i.e. after the controller's reset)
    /* verilator lint_off WIDTHEXPAND */
    /* verilator lint_off CMPCONST */
    reg we_seen;
    initial we_seen = 1'b0;
    always @(posedge clk) begin
        if (we === 1'b0 || we === 1'b1)
            we_seen <= 1'b1;
        if ((we_seen && we !== 1'b0 && we !== 1'b1) ||
            (we === 1'b1 && ((^a !== 1'b0 && ^a !== 1'b1) || a >= DEPTH)))
            $display("ERROR dpram: write with undefined enable/address (t=%0t)", $time);
    end
    /* verilator lint_on CMPCONST */
    /* verilator lint_on WIDTHEXPAND */
    // synthesis translate_on
endmodule
