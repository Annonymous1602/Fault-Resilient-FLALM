// B1  bka : parametric WIDTH-bit adder (the paper's BKA, Brent-Kung adder)
//
// Paper : Alg. 6 line 4, Alg. 8 line 6, Eq. 19, Fig. 5, Fig. 7, Eq. 26, ref. [22]
// Spec  : FLALM_SPEC 6.2 / 6.4 / 8, A18 and A48 (adder mapping), A30 (also used for
//         ADD1/ADD2 and the Karatsuba SUB)
// Golden: model/datapath.py bka_prefix() (function; the body below is not a prefix network)
//
// s = (x + y + cin) mod 2^WIDTH, cout = carry out of bit WIDTH-1.
// Purely combinational.  Subtraction is x + ~y + 1 (cin = 1).
//
// Implementation (A48, part of the frozen baseline, A54): the body is written as
// ordinary Verilog addition so that Vivado infers the native carry chain (CARRY4).
// Function and latency are those of a Brent-Kung prefix adder: s = (x + y + cin) mod
// 2^WIDTH, cout = carry out of bit WIDTH-1, unsigned, purely combinational.  The operands
// are zero-extended to WIDTH+1 bits
// explicitly (same value as the implicit context extension; keeps Verilator -Wall clean).
module bka #(
    parameter WIDTH = 8
) (
    input  [WIDTH-1:0] x,
    input  [WIDTH-1:0] y,
    input              cin,
    output [WIDTH-1:0] s,
    output             cout
);
    assign {cout, s} = {1'b0, x} + {1'b0, y} + {{WIDTH{1'b0}}, cin};
endmodule
