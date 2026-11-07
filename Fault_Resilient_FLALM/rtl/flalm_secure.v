// Fail-stop interface wrapper for FLALM. The original done remains raw completion.
// Only result_valid authorizes a consumer to read the output RAM.
module flalm_secure #(
    parameter W = 128,
    parameter NW = 8
)(
    input clk,
    input rst,
    input start,
    input [$clog2(NW):0] len,
    input smm_en,
    input [W-1:0] mp,
    output busy,
    output done,
    output z_sel,
    output security_fault,
    output result_valid
);
    flalm #(.W(W), .NW(NW)) u_flalm (
        .clk(clk), .rst(rst), .start(start), .len(len), .smm_en(smm_en),
        .mp(mp), .busy(busy), .done(done), .z_sel(z_sel),
        .security_fault_out(security_fault)
    );
    // The alarm is sticky until rst. It belongs to the current calculation
    // when the monitor has been reset immediately before starting the test.
    // Alarm connected through module ports, not hierarchy.
    assign result_valid = done && !security_fault;
endmodule
