// Balanced, exact reduction mod 8191 for 1 <= W <= 512.
// No % in synthesis RTL. Constant width at each tree level is bounded.
module residue_fold_8191 #(parameter W=128)(
    input [W-1:0] x,
    output [12:0] residue
);
    localparam K = (W+12)/13;
    localparam L = (K <= 1) ? 1 : (1 << $clog2(K));
    localparam SW = 13 + ((K <= 1) ? 0 : $clog2(K));
    wire [SW-1:0] tree [1:2*L-1];
    genvar i;
    generate
      for(i=0; i<L; i=i+1) begin: leaves
        if(i<K) begin: occupied
          if(13*(i+1)<=W) begin: full
            assign tree[L+i] = x[13*i +: 13];
          end else begin: partial
            assign tree[L+i] = {{(13-(W-13*i)){1'b0}}, x[W-1:13*i]};
          end
        end else begin: empty_leaf
          assign tree[L+i] = {SW{1'b0}};
        end
      end
      for(i=1;i<L;i=i+1) begin: internal_nodes
        assign tree[i] = tree[2*i] + tree[2*i+1];
      end
    endgenerate
    // P3-A: two folds are sufficient for 1 <= W <= 512.
    // Canonical zero is required when the folded result is 8191.
    wire [13:0] f1 =
        {1'b0, tree[1][12:0]} + (tree[1] >> 13);

    wire [13:0] f2 =
        {1'b0, f1[12:0]} + (f1 >> 13);

    assign residue =
        (f2 == 14'd8191) ? 13'd0 : f2[12:0];
endmodule
