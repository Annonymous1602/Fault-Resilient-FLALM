`timescale 1ns/1ps
module fault_campaign_tb;
  localparam W=128;
  reg [W-1:0] a,b;
  reg [2*W-1:0] product;
  wire mismatch;
  integer trials, seed, fh, i, bit_pos, detected, silent, masked, errors, rv;
  reg [2*W-1:0] golden;
  reg [31:0] randword;
  reg [1023:0] csv_path;
  residue_mul_check #(.W(W), .P(8191)) dut(.a(a),.b(b),.product(product),.mismatch(mismatch));
  initial begin
    trials=1000; seed=2027; csv_path="fault_injection/results/campaign.csv";
    rv=$value$plusargs("TRIALS=%d",trials);
    rv=$value$plusargs("SEED=%d",seed);
    rv=$value$plusargs("CSV=%s",csv_path);
    fh=$fopen(csv_path,"w");
    if (fh==0) $fatal(1,"Could not open CSV output");
    $fdisplay(fh,"trial_id,bit_position,detected,output_corrupted,silent_corruption");
    detected=0; silent=0; masked=0; errors=0;
    for (i=0;i<trials;i=i+1) begin
      a={$random(seed),$random(seed),$random(seed),$random(seed)};
      b={$random(seed),$random(seed),$random(seed),$random(seed)};
      golden=a*b;
      product=golden;
      #1;
      if (mismatch !== 1'b0) begin
        $display("ERROR: false alarm trial=%0d",i); errors=errors+1;
      end
      randword=$random(seed);
      bit_pos=randword % (2*W);
      product=golden ^ ({{(2*W-1){1'b0}},1'b1} << bit_pos);
      #1;
      if(mismatch === 1'b1) detected=detected+1;
      else silent=silent+1;
      $fdisplay(fh,"%0d,%0d,%0d,1,%0d",i,bit_pos,mismatch===1'b1,mismatch!==1'b1);
    end
    $fclose(fh);
    $display("RESULT trials=%0d detected=%0d silent=%0d errors=%0d",trials,detected,silent,errors);
    if(errors!=0 || detected+silent!=trials) $fatal(1,"Campaign failure");
    $finish;
  end
endmodule
