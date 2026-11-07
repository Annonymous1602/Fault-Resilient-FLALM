// flalm_tb_1024 : standalone self-checking testbench of the frozen FLALM top level
//                (module flalm), N = 1024, w = W = 128, NW = n = 8.
//
// Verilog-2001 only.  Needs nothing but ../rtl/*.v (no include files, no data files).
//
// Interface use (the frozen top has no host load port by design; operands live in its
// internal W-bit dual-port RAM, word i of X/Y/M at X_BASE/Y_BASE/M_BASE + i):
//   1. write X, Y (SMM: Y = X) and M words into dut.u_flalm.u_ram.mem (RAM backdoor)
//   2. drive len = n, smm_en, mp = M'_0 = -M^-1 mod 2^W; pulse start for one cycle
//   3. count clock edges until done (CYCLES = edge(done) - edge(start sampled))
//   4. read Z word i from (z_sel ? Y_BASE : X_BASE) + i
//   5. compare Z, z_sel and CYCLES with the fixed expected values below
// Expected cycles: GMM 414, SMM 333 (3S+6; SMM follows the paper equation, not the
// printed table value).
//
// Expected results are fixed constants, produced from the validated golden model of
// the reproduction (baseline flalm-paper-baseline = be8e0ee), seed 20261005:
//   Z      = X * Y * 2^-N mod M         (model.montgomery.mont_ref)
//   Z      cross-checked with model.montgomery.alg4 and model.cycle_model (CycleSim)
//   z_sel, CYCLES from model.cycle_model (CycleSim) and model.params.cycles_derived
// The testbench does not compute any Montgomery product itself.
module containment_fault_tb_1024;
    parameter W  = 128;
    parameter NW = 8;                       // NMAX / W (RAM depth 4NW)
    parameter N  = 1024;                    // operand size = n * W, n = NW
    // derived constants of flalm for NW = 8 (written out: no $clog2 in Verilog-2001)
    localparam KW     = 4;                  // width of len = clog2(NW) + 1
    localparam X_BASE = 0;
    localparam Y_BASE = 8;
    localparam M_BASE = 16;
    localparam GMM_CYCLES = 414;
    localparam SMM_CYCLES = 333;

    reg           clk;
    reg           rst, start, smm_en;
    reg  [KW-1:0] len;
    reg  [W-1:0]  mp;
    wire          busy, done, z_sel;
    wire security_fault, result_valid;

    initial clk = 1'b0;
    always #5 clk = ~clk;                   // clock period 10 time units (no timescale:
                                            // the RTL has no delays)

    flalm_secure #(.W(W), .NW(NW)) dut (
        .clk(clk), .rst(rst), .start(start), .len(len), .smm_en(smm_en), .mp(mp),
        .busy(busy), .done(done), .z_sel(z_sel),
        .security_fault(security_fault), .result_valid(result_valid));

    integer tests, errors, i, cnt;
    integer target_test;
    integer injected;
    reg [8*16:1] target_mode;
    reg [W-1:0] fault_value;
    integer checks_before;

    reg [N-1:0] z_got;

    // one complete Montgomery multiplication through the top-level interface
    task run_test;
        input [8*20:1] name;
        input          smm;
        input [N-1:0]  x, y, m;
        input [W-1:0]  mprime;
        input [N-1:0]  z_exp;
        input          zsel_exp;
        input integer  cyc_exp;
        begin
            // 1. operands into the FLALM RAM (core idle)
            for (i = 0; i < NW; i = i + 1) begin
                dut.u_flalm.u_ram.mem[X_BASE + i] = x[i*W +: W];
                dut.u_flalm.u_ram.mem[Y_BASE + i] = y[i*W +: W];
                dut.u_flalm.u_ram.mem[M_BASE + i] = m[i*W +: W];
            end
            // 2. control inputs, start for one cycle (cycle 0)
            len    = NW;
            smm_en = smm;
            mp     = mprime;
            start  = 1'b1;
            @(posedge clk);
            #1;
            start  = 1'b0;
            if (tests == target_test) begin
                checks_before = dut.u_flalm.u_core.u_pe.u_kar.security_checks;
                fork
                    begin : inject_one_fault
                        // Wait for first reconstruction-valid Karatsuba operation.
                        wait (dut.u_flalm.u_core.u_pe.u_kar.m_res1_vld === 1'b1);
                        // At the next negedge the r1 component is stable.
                        @(negedge clk);
                        fault_value = dut.u_flalm.u_core.u_pe.u_kar.r1 ^ {{(W-1){1'b0}},1'b1};
                        force dut.u_flalm.u_core.u_pe.u_kar.r1 = fault_value;
                        $display("FAULT_INJECTED test=%0s t=%0t bit=0 location=karatsuba.r1",name,$time);
                        @(negedge clk);
                        release dut.u_flalm.u_core.u_pe.u_kar.r1;
                        injected = 1;
                        $display("FAULT_RELEASED t=%0t",$time);
                    end
                join_none
            end

            // 3. cycles until done
            cnt = 0;
            while (!done && cnt < cyc_exp + 100) begin
                @(posedge clk);
                #1;
                cnt = cnt + 1;
            end
            // 4. read the result
            for (i = 0; i < NW; i = i + 1)
                z_got[i*W +: W] = z_sel ? dut.u_flalm.u_ram.mem[Y_BASE + i]
                                        : dut.u_flalm.u_ram.mem[X_BASE + i];
            // A targeted test is classified separately from the golden pass tests.
            if (tests == target_test) begin
                if (injected != 1) begin
                    $display("FAULT_TEST_FAIL injection did not execute");
                    $fatal(1);
                end
                if (dut.u_flalm.u_core.u_pe.u_kar.security_checks <= checks_before) begin
                    $display("FAULT_TEST_FAIL no arithmetic operation was checked");
                    $fatal(1);
                end
                if (dut.u_flalm.u_core.u_pe.u_kar.security_fault !== 1'b1) begin
                    $display("FAULT_TEST_FAIL checker did not detect injected fault");
                    $fatal(1);
                end
                if (security_fault !== 1'b1 || result_valid !== 1'b0 || done !== 1'b1) begin
                    $display("CONTAINMENT_FAIL fault operation: alarm=%b valid=%b done=%b", security_fault, result_valid, done);
                    $fatal(1);
                end
                $display("CONTAINMENT_PASS fault rejected: alarm=1 valid=0 raw_done=1");
                if (z_got !== z_exp)
                    $display("FAULT_TEST_PASS detected=1 final_output_corrupted=1 cycles=%0d",cnt);
                else
                    $display("FAULT_TEST_PASS detected=1 final_output_corrupted=0 (masked or corrected) cycles=%0d",cnt);
                $finish;
            end
            // 5. check
            tests = tests + 1;
            if (done === 1'b1 && busy === 1'b0 && cnt == cyc_exp &&
                z_sel === zsel_exp && z_got === z_exp) begin
                $display("PASS  %0s  cycles=%0d  z_sel=%0d", name, cnt, z_sel);
            end else begin
                errors = errors + 1;
                $display("FAIL  %0s  cycles=%0d (expected %0d)  z_sel=%0d (expected %0d)  done=%b busy=%b",
                         name, cnt, cyc_exp, z_sel, zsel_exp, done, busy);
                if (z_got !== z_exp) begin
                    $display("      Z   got      = %h", z_got);
                    $display("      Z   expected = %h", z_exp);
                end
            end
            // idle gap between computations
            repeat (3) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        target_mode = "GMM";
        if ($value$plusargs("target=%s", target_mode)) begin end
        if (target_mode == "SMM") target_test = 4;
        else if (target_mode == "GMM") target_test = 0;
        else begin
            $display("Unknown +target=%0s", target_mode);
            $fatal(1);
        end
        injected = 0;
        checks_before = 0;
        tests  = 0;
        errors = 0;
        rst    = 1'b1;
        start  = 1'b0;
        smm_en = 1'b0;
        len    = {KW{1'b0}};
        mp     = {W{1'b0}};
        repeat (4) @(posedge clk);
        #1;
        rst = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        $display("FLALM testbench: N = %0d, W = %0d, NW = %0d", N, W, NW);

        // GMM random: expected z_sel = 1, cycles = 414
        run_test("GMM random", 1'b0,
            // X
            {128'h6c69a99822a469d09fe8dfeb7911dc02,
            128'h8554749b2c00434bbe5e15eec122ed4c,
            128'h038e59ae3b1a1cd97fc1944bc67e0871,
            128'hb6373a468591e4a3c51ddcfdb6c0c265,
            128'h9de78803fcd40acc4f8f85c842dfe9d0,
            128'hf8206796280ced30c2638f92f59f29d1,
            128'h37df842bc53706560da233b826892966,
            128'h4bd246ad461e2ef5600f136b4b20ff6c},
            // Y
            {128'hbb3657fc2da5b38c11affcc7f7598671,
            128'h8892d58bc337fe457f56972ac155a617,
            128'h96ad3a762efd7e1eab581aafe7ecb27a,
            128'h1245cf8beedc4b306d7da334a2fc40f6,
            128'hd2c290910e3c33d4116f76666e797354,
            128'h0d843e4ca2ed005a0571a72c9c42c21c,
            128'hf98441ad10762e5e4227322f3efce249,
            128'h5c82bbd6527178789162a6e8c9720cf6},
            // M
            {128'hde1c156167e833775deb2534264b5e5d,
            128'he3fc6dfd027b9df7e27e27943a32da3c,
            128'h61345fccdb36c31cb4cb70b3963078a8,
            128'h69cbe66ca40bdac8712f4803e2342e39,
            128'hbcb8863448d14de2892b360e49853c6b,
            128'hb77f62e41c9b4737176c645e059d330a,
            128'h859b0f5e8dabb5771848f9d0278ceafa,
            128'h665bce744bdc41648bb1cc4246de2401},
            // M'_0 = -M^-1 mod 2^W
            128'h25ff94b08d8dd28587295b2611ce23ff,
            // expected Z = X * Y * 2^-1024 mod M
            {128'h2a715a14d25fa97ad43187b7bc5d1498,
            128'h54f23b9159fe37d3927748f8a2ba9d31,
            128'h7b7733c67efde25eee75a03af4173cd6,
            128'h798f3cf2cb5f8ec4821d6aa5f1c23911,
            128'h12865fc33a9626a1140fffb1c931a70f,
            128'h4d5e07974013c311f990642e56b4893c,
            128'h6ca8db0a8ca82bf84f83436d9c1fd7a1,
            128'h0b3ad1fd631c8ae503cc936d201ebc50},
            1'b1, GMM_CYCLES);

        // GMM max operands: expected z_sel = 1, cycles = 414
        run_test("GMM max operands", 1'b0,
            // X
            {128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hfffffffffffffffffffffffffffffffe},
            // Y
            {128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hfffffffffffffffffffffffffffffffe},
            // M
            {128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff},
            // M'_0 = -M^-1 mod 2^W
            128'h00000000000000000000000000000001,
            // expected Z = X * Y * 2^-1024 mod M
            {128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000001},
            1'b1, GMM_CYCLES);

        // GMM M<2^(N-1): expected z_sel = 0, cycles = 414
        run_test("GMM M<2^(N-1)", 1'b0,
            // X
            {128'h24cbe0c64a64a67ed9a58eaa24de6022,
            128'h6c90574cd47764cdacc3497ce1ad21e5,
            128'he82ea6321c3077e99d3a744a0add6abc,
            128'h9deee537ac0623939268c31c9326ffca,
            128'hcbac6e66b4d9fbb85612aa9fe674a0fe,
            128'ha693a18699a287e4dd33d7c3f1eb7eeb,
            128'ha8ef1cb0a88609d74d3af59858f03253,
            128'h401f74ef3581fb67e1f16e7af4f673f8},
            // Y
            {128'h384bdb343ec0f53a4000bd7592abac46,
            128'hc038870b1427b036c60b4c8123c6d573,
            128'hdda801364db2a469f3d14a80fe6a125e,
            128'hdc06fb57702fede9b0c191bc00c0909c,
            128'hcb79f624f2d9f6ae8a4a4357b43ed2dd,
            128'h7b63b559a12b0378673971629eba0b93,
            128'hccfdfff093b83a648cc13d322660b5f9,
            128'h32d8f820f2cd0aef98bc890b506eacce},
            // M
            {128'h5ef27e3f73832518b9b2bf5a3ff7cd82,
            128'h0a5da9c85b41cf3eecee0dbe2d466217,
            128'h4622ee8d03981dd85c40c55d896f0027,
            128'h46d4a03ec26289ec0695987a04d7dc4b,
            128'h2ac284084c6ee6aabe659a754449708c,
            128'h4f6ac194f22c20c3ec2e17a2948e14b3,
            128'h515fcaa14df50aa9924f9e69f17199b8,
            128'hee07da33c9d5839acec1fc08009e911d},
            // M'_0 = -M^-1 mod 2^W
            128'hc2f18e3896ecb704f0e352b3a9d946cb,
            // expected Z = X * Y * 2^-1024 mod M
            {128'h2916a167a8f6ec6c2b1ea732a4edfaca,
            128'hbce76afa2b2a8aa40ebb0113a6442f82,
            128'h2bfbbf6cd1db888785d307c132e40463,
            128'h841c9124eee5cb4cf908a0216e0a0adc,
            128'hbd9e4375475ec6188dfb02858801bd14,
            128'ha1cb44d2a18693366acbc8420dc88d79,
            128'hc8b866763ac98581696ed332d0744dd3,
            128'h9fb3c6456de23f1612cfe24bbdc69bc7},
            1'b0, GMM_CYCLES);

        // GMM X=1: expected z_sel = 0, cycles = 414
        run_test("GMM X=1", 1'b0,
            // X
            {128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000001},
            // Y
            {128'hde8c4d91a5d1804378d9b70515696516,
            128'hb405bb76c190e85757dd8ee547b0c179,
            128'h6030b80a7a015f7d5dc76b09f440eb72,
            128'h1621493ccf3c5f88101af1067837a6eb,
            128'h028dcdfdb5093967c1ff593ef33bb7ae,
            128'h7de8ab5e553e61d5e0fc7aaf8ee42307,
            128'h10f959b5e0f577546ac696678033ed4c,
            128'h0a2cfb6006a2c00e877572ad01ef24a0},
            // M
            {128'hf5b7f9248de6ff40598ef006af834fd7,
            128'hba952af16fd599fefa55bdc465f95ca2,
            128'h128a82e14ec8d346f154027a71069266,
            128'hcfa22ebf576d058ad14cac0cedb26a70,
            128'h31be9abec30315f94d51175b0d9a4fe3,
            128'hdf9d687920ee2797bd7be3ac40dc1c67,
            128'h8286be963d0c759612f8e0a552e73b62,
            128'h4559690f7c2e7ada5e1bb367632894fd},
            // M'_0 = -M^-1 mod 2^W
            128'h66db36fcf300425c199cc291a714d7ab,
            // expected Z = X * Y * 2^-1024 mod M
            {128'ha3e776d12a2afba3bc8ecc330715955d,
            128'he0c1471f6e1f91c8ad2bf5b371a61de9,
            128'h57c63afd1adc55355a5e24f64d34de32,
            128'hc417eda08e7390dda84d9cb0a4772d97,
            128'h3445dbffc9632739af674ad3e917b914,
            128'hd8d94f5978bfa75f241f432e2ba57f59,
            128'h371488def6a343a842c2626a98aa58f4,
            128'haf09996bf837f63a185944de107e9b33},
            1'b0, GMM_CYCLES);

        // SMM random: expected z_sel = 0, cycles = 333
        run_test("SMM random", 1'b1,
            // X
            {128'h172ece72e93875b07fd4dcb0dc6bde20,
            128'h06e079dc05bf63ce3aa78fe5ade3c3e7,
            128'hcd7765fc09e68937620bca1d8b14a94b,
            128'hb5bb4d9733e88e35007b071a4e963959,
            128'had077420808c448702cb5eec646a0a28,
            128'hf60a80c3affd62e7b97ebfdc8dda4743,
            128'h7f35bb182f3e83a23d6b328b442b90b7,
            128'h8f0918653f0b20a17d3e0ac68c47e88b},
            // Y
            {128'h172ece72e93875b07fd4dcb0dc6bde20,
            128'h06e079dc05bf63ce3aa78fe5ade3c3e7,
            128'hcd7765fc09e68937620bca1d8b14a94b,
            128'hb5bb4d9733e88e35007b071a4e963959,
            128'had077420808c448702cb5eec646a0a28,
            128'hf60a80c3affd62e7b97ebfdc8dda4743,
            128'h7f35bb182f3e83a23d6b328b442b90b7,
            128'h8f0918653f0b20a17d3e0ac68c47e88b},
            // M
            {128'h993d3c733c76fa5410d05c09bdb29253,
            128'h4e44856ad5336f3494be3f8b013c613c,
            128'h3311186e150c175706f4ba20d151ba93,
            128'hf8e47aeb52dd34ca96f43b5cb960b988,
            128'h6b7f2605761bf112a2e9075abe48dcdb,
            128'h9ade72c62580f5808deea47ef163f185,
            128'h7d2a397b88be660274afff8977fa596e,
            128'h620aa8e4872926d6aa63b1303e69b179},
            // M'_0 = -M^-1 mod 2^W
            128'hb8a13807e1dc47021a479910c5e11737,
            // expected Z = X * Y * 2^-1024 mod M
            {128'h67f205eafb1e22d3f769870d35ee9635,
            128'h1b5e4d0d5987f744c6a15495dfb522ba,
            128'h044b2da2d08d8d886a879c90e1315587,
            128'h3a9da8b1284d827e2c727b24b682eace,
            128'hb4f7b7a88336c063d321ef475c9809e7,
            128'hc3c4dc5a2e747cfeae781c65d8b80101,
            128'hf3e667f8e2822d3416db659214cd8028,
            128'hdeaa0cbb8bf8e6fc1e7213fa89f8cb5b},
            1'b0, SMM_CYCLES);

        // SMM max operand: expected z_sel = 1, cycles = 333
        run_test("SMM max operand", 1'b1,
            // X
            {128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hfffffffffffffffffffffffffffffffe},
            // Y
            {128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hfffffffffffffffffffffffffffffffe},
            // M
            {128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff},
            // M'_0 = -M^-1 mod 2^W
            128'h00000000000000000000000000000001,
            // expected Z = X * Y * 2^-1024 mod M
            {128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000001},
            1'b1, SMM_CYCLES);

        // SMM M<2^(N-1): expected z_sel = 1, cycles = 333
        run_test("SMM M<2^(N-1)", 1'b1,
            // X
            {128'h61e66d67c5c143eb5357bd36e3926842,
            128'h4d8fc63cd52a577a1b18c38d637d4ecd,
            128'he2a177ed14d655bb439d70cdc444a9e5,
            128'he751985dc63f5d856eb18991a612a981,
            128'h5245f7e119dcb3ab998f78be385d7299,
            128'hb7a7c793a42a5185f3adf4741d83fc4f,
            128'h82992de11047dd160d2fcae97bab14cf,
            128'h7eba2b3383d2e57056cee981537cfd59},
            // Y
            {128'h61e66d67c5c143eb5357bd36e3926842,
            128'h4d8fc63cd52a577a1b18c38d637d4ecd,
            128'he2a177ed14d655bb439d70cdc444a9e5,
            128'he751985dc63f5d856eb18991a612a981,
            128'h5245f7e119dcb3ab998f78be385d7299,
            128'hb7a7c793a42a5185f3adf4741d83fc4f,
            128'h82992de11047dd160d2fcae97bab14cf,
            128'h7eba2b3383d2e57056cee981537cfd59},
            // M
            {128'h7e9c82840d888183e0ed62712e6c819e,
            128'h5196d241d59a796de3e91efed0a180af,
            128'h21df9eb01b920a71baaf5adc94e8cd83,
            128'h874a8d541ca38356bd6e02b1a40c6bae,
            128'h3399c672c9fba7abb9c302d5684313d3,
            128'h33d602a26c689a4dc1cd11a2f07af7a6,
            128'he284d5947f889240894b8c964332c2d5,
            128'hde53e0cb366e81970dacb1f270f52f83},
            // M'_0 = -M^-1 mod 2^W
            128'h618643d2d4980f690d54759ac9b128d5,
            // expected Z = X * Y * 2^-1024 mod M
            {128'h23903b629811c49502516647e05fe81a,
            128'h93f9830ea457f993d731e584df53fd8e,
            128'hde84669cc10cf0504833dcd58ccefb20,
            128'h3e02997dff3fdbe427aac5b3b2cc8cc0,
            128'hfbe9255f442cd53911ee2818c65b49f0,
            128'h80001e067aa17730cb151aa0b4e459bc,
            128'h69cf752db2234c9ef934ff2fca33d98d,
            128'hccc4380bdccf6432e1a342013b62eddc},
            1'b1, SMM_CYCLES);

        if (errors == 0)
            $display("RESULT: PASS  (%0d of %0d tests, N = 1024)", tests, tests);
        else
            $display("RESULT: FAIL  (%0d of %0d tests failed, N = 1024)", errors, tests);
        $finish;
    end

    // watchdog
    initial begin
        #10000000;
        $display("RESULT: FAIL  (timeout)");
        $finish;
    end
endmodule
