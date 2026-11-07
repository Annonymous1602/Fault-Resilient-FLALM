 the frozen baseline, A54): the body is written as
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
