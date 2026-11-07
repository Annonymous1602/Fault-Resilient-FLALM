// B3  mulq : AW x BW unsigned multiplier (one quarter of the 2-cycle MUL)
//
// Paper : Eq. 20, Fig. 5, Sec. IV-B-1 (DSP blocks, registered inputs/outputs)
// Spec  : FLALM_SPEC 6.1, A19 (plain '*', Vivado default inference, no attributes)
//
// Combinational.  The operands come straight from the Karatsuba mi1/mi2
// registers and the product goes straight into the mul2c t-registers.
module mulq #(
    parameter AW = 17,
    parameter BW = 17
) (
    input  [AW-1:0]    a,
    input  [BW-1:0]    b,
    output [AW+BW-1:0] p
);
    assign p = a * b;
endmodule
