// B2  csa22 : WIDTH-bit 2-2 carry-save adder row (WIDTH parallel half adders)
//
// Paper : Eq. 10, Fig. 4, Alg. 6 line 3
// Golden: model/datapath.py csa22()
//
// a + b = s + 2*cy.  The carry row is NOT shifted here.
module csa22 #(
    parameter WIDTH = 8
) (
    input  [WIDTH-1:0] a,
    input  [WIDTH-1:0] b,
    output [WIDTH-1:0] s,
    output [WIDTH-1:0] cy
);
    assign s  = a ^ b;
    assign cy = a & b;
endmodule
