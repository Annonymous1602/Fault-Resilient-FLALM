// B2  csa32 : WIDTH-bit 3-2 carry-save adder row (WIDTH parallel full adders)
//
// Paper : Eq. 9, Fig. 4, Fig. 7, Alg. 6 line 1, Alg. 8 line 5
// Golden: model/datapath.py csa32()
//
// a + b + c = s + 2*cy.  The carry row is NOT shifted here; the user shifts it
// ((C0,1'b0) in Alg. 6/8) and decides which MSB is dropped.
module csa32 #(
    parameter WIDTH = 8
) (
    input  [WIDTH-1:0] a,
    input  [WIDTH-1:0] b,
    input  [WIDTH-1:0] c,
    output [WIDTH-1:0] s,
    output [WIDTH-1:0] cy
);
    assign s  = a ^ b ^ c;
    assign cy = (a & b) | (a & c) | (b & c);
endmodule
