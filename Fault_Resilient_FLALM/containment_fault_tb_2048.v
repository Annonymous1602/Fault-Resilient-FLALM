// flalm_tb_2048 : standalone self-checking testbench of the frozen FLALM top level
//                (module flalm), N = 2048, w = W = 128, NW = n = 16.
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
// Expected cycles: GMM 1590, SMM 1233 (3S+6; SMM follows the paper equation, not the
// printed table value).
//
// Expected results are fixed constants, produced from the validated golden model of
// the reproduction (baseline flalm-paper-baseline = be8e0ee), seed 20261005:
//   Z      = X * Y * 2^-N mod M         (model.montgomery.mont_ref)
//   Z      cross-checked with model.montgomery.alg4 and model.cycle_model (CycleSim)
//   z_sel, CYCLES from model.cycle_model (CycleSim) and model.params.cycles_derived
// The testbench does not compute any Montgomery product itself.
module containment_fault_tb_2048;
    parameter W  = 128;
    parameter NW = 16;                      // NMAX / W (RAM depth 4NW)
    parameter N  = 2048;                    // operand size = n * W, n = NW
    // derived constants of flalm for NW = 16 (written out: no $clog2 in Verilog-2001)
    localparam KW     = 5;                  // width of len = clog2(NW) + 1
    localparam X_BASE = 0;
    localparam Y_BASE = 16;
    localparam M_BASE = 32;
    localparam GMM_CYCLES = 1590;
    localparam SMM_CYCLES = 1233;

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

        // GMM random: expected z_sel = 0, cycles = 1590
        run_test("GMM random", 1'b0,
            // X
            {128'h34d09df21ed64de89ebbf9ae48be2025,
            128'heb721424062ed56257f298d7aaa97d7a,
            128'hdef78386f88a7f050187baeaa80fe308,
            128'h4aeefb75c26fb80542e1df6df4ca8a61,
            128'hd66b96f5bebe822535f9f0241e7c98de,
            128'h1a0e350432ae6832f29c99e6abe185ce,
            128'h01c35fe4eca134e964b3be907a031ecc,
            128'h11577d091c7646f5868deed10c1b8efd,
            128'hd0b564d24496d8f3abb20eca4ef60fff,
            128'hceef75a8783755ac2559f6f8223c8b0f,
            128'h427b30d4c43dce108b5cbcef13898961,
            128'h256d6dc3c00758cb1615ceced8b1439d,
            128'hdb2e2fb8265da9a884746967bec763e3,
            128'h234046e324a6569ba20d0d4b8ee23416,
            128'hb55dae9364eb8461ba3d5719661066d1,
            128'hcd1095bf2835841777de62f9089cd5aa},
            // Y
            {128'h060f520a29f7e45f15509c99b2235847,
            128'h7b13b17cf8ec480e1344e230db66faf3,
            128'hdac73fa25c5b13addf72ee315e939f20,
            128'h17831e2f3d58d7c4e5c1e3a24a6504c0,
            128'ha2eff3aa453d610f96a640b0ea24e1db,
            128'hd83ea7bf6018ca57510aeb7c8ed87ed9,
            128'h2c22ece72b079660063d57513b9e8d5a,
            128'hdab3ddab18444ccfa65bf718a909fb5b,
            128'hd49190599cdfd5b58ad86cbb763ee1a8,
            128'h64997cdfe12cf1201add07194f5d2525,
            128'hd0d27d4007cce5267210414f12bd8e10,
            128'h735fd3a91d50f2f1a9149b3db416f686,
            128'h7d6466c9903bc162675abe0886614407,
            128'hef9905c90f8f0d536759b9e8e90aa91b,
            128'h6a1f3314ba45ead529ebe677e1e6b4f2,
            128'h3b97bbda711534aa30ff1bc746074614},
            // M
            {128'h876365e26bc954e772234c2b88892501,
            128'h9332eedabcb9ef4ec149e45ee98042f7,
            128'hc93f3b604d46b8b21047d151df35e27f,
            128'hd1901f4ea6424b78757941443afae020,
            128'hbbcaf272e5451796c751eb7075e9181b,
            128'h2c09ed2f619cbfffe6f08d2592c2f104,
            128'hd6f60127d49e2e87dc3e61d5de549dfb,
            128'he3d6fe58f2fbbc057ac9e970a33b73cd,
            128'h6a4d9b627b7236cc7698ba5f53256a54,
            128'he235c040888077fc7b9db2eee912e758,
            128'h6025cc01a91a26c84546e249306aa19b,
            128'h85f002050ac33c843a0e0d7836b87741,
            128'hf034a1b522e318efbb14ef0e1ee158f6,
            128'hc76dab9742fdafa75e3e014949f73caf,
            128'hdc6b439e3ef4648fe2d1c8f8c56d8f48,
            128'hc15db330f88d0adb6205b29846a036b5},
            // M'_0 = -M^-1 mod 2^W
            128'hf9f433e96416b5fcf59a864f068e7863,
            // expected Z = X * Y * 2^-2048 mod M
            {128'h6e36cc40303e821b26a1e57e53fe9da3,
            128'h63090607f48624f9a3204f5f7fdc09bb,
            128'h2914ef4aeb5cb548d49aea62b97094b8,
            128'hdeed46a3f5ce9e29fbfb5592b901078f,
            128'hd53a4c8d58afacfeba358df6e1101f37,
            128'hd228e647b39e0dc3687bfa7d1006256e,
            128'h87cb423d303574e7a1145d8a3e7bb787,
            128'h34a25798ace77dbfebbd75342d9dd471,
            128'hd756558a411a9bdc1da362008cbef532,
            128'hd565bf6cb410da33837409dac4f33e96,
            128'h6efa92cadf077ce2cf247f87c2655671,
            128'h6129347946160229122c1e7b19680396,
            128'h322a0e2b761450e5039f6da2de08f97e,
            128'h221a3c0213e1295d6fe06883954ec9bb,
            128'hefd7dc7ebc5309425a2db8e1b4382e05,
            128'had2e421c4612e99fa71199dfef365918},
            1'b0, GMM_CYCLES);

        // GMM max operands: expected z_sel = 1, cycles = 1590
        run_test("GMM max operands", 1'b0,
            // X
            {128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
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
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
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
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff},
            // M'_0 = -M^-1 mod 2^W
            128'h00000000000000000000000000000001,
            // expected Z = X * Y * 2^-2048 mod M
            {128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000001},
            1'b1, GMM_CYCLES);

        // GMM M<2^(N-1): expected z_sel = 1, cycles = 1590
        run_test("GMM M<2^(N-1)", 1'b0,
            // X
            {128'h2a58de542bff5bca29d8bf84ad6de29e,
            128'h3cab65c3e0541667a1ae95fe9024044d,
            128'hf59ca5995d115b4cf34cd823e7de171c,
            128'he3ea3d1940351a24c04cc34ce738528b,
            128'h140f10c7aef097c51c3e4fe31c8dbe2a,
            128'h33e62315bb53360e8a92b39d81a2f640,
            128'hf469f37a44b1d4b5561a5fa2c91cde54,
            128'h9a5a5fc1c83c675117a700980067fecd,
            128'h3d12a4e07d7e142793e324a98133f064,
            128'h2458bebf693e7e3931592aaa776d5adc,
            128'hc159e031c51d80f934f02a9f02e4f730,
            128'h420bb8622faf0cb4a6822649e78571b4,
            128'he7496c32bed63d3af6e5bd02213f8c90,
            128'he41b8aa49d2b6a17dc164c51a9914893,
            128'h8b68845aac559e2093ccd4d3597734b1,
            128'h2186282f0bdca401a38b188e774a77a0},
            // Y
            {128'h18e25124cf9cf287b5645ccc48437028,
            128'hb7a01696d139865e7a79e6475e48b5d2,
            128'hb85f48fc46fd301b1c08dd904ec42ba8,
            128'h538b21569f52a95c42d42bae253bfac6,
            128'h3f8fe5eaccea4540aec93f17a4a96f30,
            128'h895d6976b83922509fef147582e331d1,
            128'h8406128b8506d6d55941d065f7972f31,
            128'h04d09042cfedddb3f769d283fc74b4c5,
            128'h8cd991bd69c7a0c87bdb04042dad65ff,
            128'h1ee3de59bc160624eac7fc77a4de435f,
            128'h4c7821f3426692b7fb6dcb6662932fc4,
            128'hf09c82b2796d9e77d98ad442e438c304,
            128'hae1e1fd9ca16b5e131b3565160f38a54,
            128'h8b3fd8a715f84429246615a2888d024f,
            128'ha3cb50902cc64ab0dd2872a5559abe14,
            128'hf8ef06a7604771ac800ccd6534051c72},
            // M
            {128'h41194f7e87b5574f002ce70ba01f12bd,
            128'hfb04a1ec03725e3426a79bc0e21b18cb,
            128'h2a0a8a60028687df42c5c2b239299f61,
            128'h776d074ec1b6f3efe7015502210bd12b,
            128'h1aaf52aeee61b48495f655b011165b58,
            128'he139e8a40e1843db868aff2cf2987abe,
            128'h2fa26d732922a89dde18be1224d02dd7,
            128'h5ff95bf93e0b0cc30dad7e8395289af1,
            128'h288e7e05977ca4e0a5586ae945049f9c,
            128'h2610ccb1c65a3b74d97ab5f8b3b5b5cc,
            128'h6813faa16e8f02caa1520541617a26b7,
            128'h7c158474269bb5baba0adf1812df01fa,
            128'h10a455baabcfc18a01f8aa2a9e02b323,
            128'h17974cb278f9b1596ef496023427a9c4,
            128'h64fadaadf1a18feae3c4fb365d3c3fcd,
            128'hca4a56c52d200dea30ad9803642150e9},
            // M'_0 = -M^-1 mod 2^W
            128'h05e8870087c739aed54b29ad8f3f78a7,
            // expected Z = X * Y * 2^-2048 mod M
            {128'h01ccfdf7f5f5a0a6cac2b3ff4477b588,
            128'h335c3f9e38d3f2e03872708ecbececcc,
            128'hf21888a06f0d7250a146b9bc0de222d2,
            128'h3a29bebbfefcbde3466110e660144da4,
            128'h15258729817d70b2153cad3858490dd0,
            128'h96c76aaf82528352e499f69f75566968,
            128'h5e672c64ffbf595f1b2b3fa7eef0c99e,
            128'h3af3d0ebc7b4c1912cca000178c91195,
            128'ha678c316debbc243217aa10b877c6aae,
            128'h511afadac7e42c371223feb71b5aef8c,
            128'hbba89cf3ea6924dfbb5229461ea4a4e7,
            128'hfb37eea17522d2bd6cd5325fb5c1a012,
            128'he2a119fe541f2a3648ae1d56cd2544f6,
            128'h9b0f665c149b2c49935432b03ebe0cfe,
            128'h12c527f31b6194ded7ab1d068ab3fc26,
            128'h6e806c0ac35bece8541830d7d8d78a9e},
            1'b1, GMM_CYCLES);

        // GMM X=1: expected z_sel = 0, cycles = 1590
        run_test("GMM X=1", 1'b0,
            // X
            {128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000001},
            // Y
            {128'h6f4d8586b92c2953c4373915a65a1106,
            128'heaa6c92f1d4319c738dc51781f8353cc,
            128'hcdce9f791b87132abdb184f17fb6f4b8,
            128'h02733a4c0a2a8c724c905fa97370d62c,
            128'h4264c1b1fb1742dce1d53fba9b4009eb,
            128'h457c80ee7f7241680f4a806e78547fc7,
            128'h1d91d8394fad86cf49e965f8620e3c24,
            128'hb17648312d202ac6107b81231b3235df,
            128'h034a5de39ae2125a2543a5ac477b5024,
            128'h6d2071c234d79077b987a24ef0ca9605,
            128'h8b8e2b047bcf2c9d46295f89de57e500,
            128'hc9a786d4462756c721fa90aeb9caa06a,
            128'h50c86b6ffc7023638290152195d40d1a,
            128'h06b050e3edd32f87d4f9181f1e7665ea,
            128'h74f455fee4c2b97590e98590060ea271,
            128'h3278f57e29261015de0332bf1fb5ceb9},
            // M
            {128'hf631e3d2f48ecd690cee99c793613564,
            128'he1b0438714ccb2a3d24041b56b04b142,
            128'hd2cb41184c1aedb97a47e3edf42dfa7a,
            128'h5338b9282c1c3b88e6c2d3c01ddc0a0a,
            128'h97b94489d3bd454f311ca090923a4bc9,
            128'h1e1272f5e8a075ff0841ce17709e902c,
            128'h8bfc8d3116d14e7dc3f120498beb4f2b,
            128'h5ebaf960e8f83daf233452c15044ab66,
            128'h9880ddade40a0865dddc5b582f7178e8,
            128'hb54ad316578a3b0e29ad045b2eb68842,
            128'ha2571e5003c032052d62022525a363b5,
            128'hb2dcf547ed4ea2b4bc222b1b0776aa71,
            128'h95dedd4e00fbde65713af7e75369f77b,
            128'hedd28df4f4bacceda19348dc0c400ede,
            128'hf5e388e13d7a7e11e798823b044471c2,
            128'h2b11d7e24beb75df241151fb3f9c1f13},
            // M'_0 = -M^-1 mod 2^W
            128'h52dbfb5a66bc1e756a605ce346e97ce5,
            // expected Z = X * Y * 2^-2048 mod M
            {128'h803e45f7eaf7ff5942587f9e7ceacb80,
            128'h9013356efe72f7ed806e63e35a2acda7,
            128'h0165bfe67140b721e4c1ad5cec010979,
            128'hf08388643366cc46b7b6880fb02ae316,
            128'h6fab109a4ad335c55d10d624ce94a266,
            128'h2b652505944f4d08cac1d2142a2e6d8b,
            128'h7a373b68ae6d41f902a192a30d2b93f9,
            128'h360020c51b5d66019389e21aa66275f9,
            128'h156cc149d3af7a0938a19815ee4ee1df,
            128'h9f94fb993fbaee773ebdbc7adbcea26d,
            128'hdb2408e0842a52974e6bdcb767de6329,
            128'hee07c6f463a8446bcb7afee558198faa,
            128'h39d9f2a22096f123c527367cd9ac8d22,
            128'h9c161e6f13b40df48349e46af31d06e9,
            128'hd7125380d52715cea6b7ddf7f341638b,
            128'h024952545a4c3171ce33a28881702429},
            1'b0, GMM_CYCLES);

        // SMM random: expected z_sel = 0, cycles = 1233
        run_test("SMM random", 1'b1,
            // X
            {128'h33cb905a8cbd904e945a5f832cbffbbd,
            128'h10e34ac41a78d3717dbf615e15dbf878,
            128'h2f33e2fd799bbccffd03be3ba113ba6d,
            128'h2e334f0ca7ae48331421e9095a65fed8,
            128'h53520ff3bb047d649bbe51eac3a1929e,
            128'h2ac6f874c553d11cff4daad625eba177,
            128'hcd64b80a2ff0d9bdf558752fae8d7c92,
            128'h10db84719e9a9c45e0542f4029068169,
            128'h12402d80a4c68bd27e128b60654b8c6e,
            128'h133da6dbea35e9c76d4c4acdbdcb847d,
            128'hfdb2d4f560d7b5b73beb8a41fa0db39c,
            128'h1e3c47f38c6e60bdd424accaa38a9d9a,
            128'h6d3536608021f6a91556a54adde86124,
            128'h006866704e40e5442910e1a7b7eece07,
            128'h30a545440ba683557cc36aff819d5353,
            128'h811b20ef1080675ec65f7615dc6e2801},
            // Y
            {128'h33cb905a8cbd904e945a5f832cbffbbd,
            128'h10e34ac41a78d3717dbf615e15dbf878,
            128'h2f33e2fd799bbccffd03be3ba113ba6d,
            128'h2e334f0ca7ae48331421e9095a65fed8,
            128'h53520ff3bb047d649bbe51eac3a1929e,
            128'h2ac6f874c553d11cff4daad625eba177,
            128'hcd64b80a2ff0d9bdf558752fae8d7c92,
            128'h10db84719e9a9c45e0542f4029068169,
            128'h12402d80a4c68bd27e128b60654b8c6e,
            128'h133da6dbea35e9c76d4c4acdbdcb847d,
            128'hfdb2d4f560d7b5b73beb8a41fa0db39c,
            128'h1e3c47f38c6e60bdd424accaa38a9d9a,
            128'h6d3536608021f6a91556a54adde86124,
            128'h006866704e40e5442910e1a7b7eece07,
            128'h30a545440ba683557cc36aff819d5353,
            128'h811b20ef1080675ec65f7615dc6e2801},
            // M
            {128'h82b41c84b4ae8dd8b54c53b8b9abbb44,
            128'ha32216accf0756ce40ba220d29a36281,
            128'ha521cf27b38f3323401cf55f1588b8ab,
            128'hda9e00d0e0781fcbbd319c29e511d84f,
            128'h877e21ae91eca2b37389f276cbb5a560,
            128'h5cd39ef3dedc7e97230320e348ef8c4e,
            128'hee61f909819039a5d4c83429ef3ec5a5,
            128'hd140ddb21b21b1ce436657ae242989a8,
            128'h53ec5e1ed1d36210e0417cde27edaf3a,
            128'h03e3118130b9ed862984cb079f10efcc,
            128'he3df7186aae9453cd7b56c0d40757250,
            128'h4dcb192bb49de25bcfefde0821a7f554,
            128'h64d2ed702a152a5654bfba56743d8e63,
            128'h7652c7e6afd991c1d9918d6994a09587,
            128'hee7fa0e42036d70e919a195112e63bc8,
            128'h851b144c92bc2312f387e63e195b7551},
            // M'_0 = -M^-1 mod 2^W
            128'h1c0e18d062a448ebcecbd4c689170c4f,
            // expected Z = X * Y * 2^-2048 mod M
            {128'h271e363e84df27b73d4318e2fe4d7ed0,
            128'ha7940eb7992b0818e70d448a1918840e,
            128'h784d0b2ba5faf9b52ab51aa5c3c7c361,
            128'hd65ac8f37120c6a74328c34ca5d026f9,
            128'h0fc664b926d3f49cb942cd2b38640455,
            128'hb2a7f18e50801775f466e16133e38564,
            128'hea79b7f1fcd7dc137aa235df2efa6336,
            128'hc0e795e4c785440172f45a21474a0107,
            128'h4a59619a32c24949a45dd788ef30c5d6,
            128'h099133e0e1e3ff496278decac1d3313e,
            128'h3025a5251715d6aebbb5e2e4e10d993a,
            128'he8f3c074cacc396cf3d98c463cdea4b6,
            128'h3ac655f9f735c0c579449ec78e26842e,
            128'ha77e7eaab093c68c344f60807402493a,
            128'h57b6ef22af5c2b9c801ac99cdf4e2185,
            128'h6f77603c9420f6d33d5b1e95bae4d58f},
            1'b0, SMM_CYCLES);

        // SMM max operand: expected z_sel = 1, cycles = 1233
        run_test("SMM max operand", 1'b1,
            // X
            {128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
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
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
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
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff,
            128'hffffffffffffffffffffffffffffffff},
            // M'_0 = -M^-1 mod 2^W
            128'h00000000000000000000000000000001,
            // expected Z = X * Y * 2^-2048 mod M
            {128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000001},
            1'b1, SMM_CYCLES);

        // SMM M<2^(N-1): expected z_sel = 0, cycles = 1233
        run_test("SMM M<2^(N-1)", 1'b1,
            // X
            {128'h24430b3b5ab1664889282cce6ced5371,
            128'h759161c48bf8ad7f92cd5adf9fe01ea0,
            128'h6ab83b0a51902758e171cc20e8650683,
            128'h89883f6c3d3f23c54292a8fec71210ed,
            128'h9a51a1e5db23c1751d1f7b7dd777220b,
            128'h9cf4b68eb9cbdb8c3e48a59456dd8554,
            128'h51908234c19b268a34e9f85a810af6d7,
            128'h4126744056963a06708214260a7a38c7,
            128'h407d202743fec69da269d196495be4bb,
            128'h37cce16df3342871c272d0c128986e54,
            128'h23aa7e5efcaed9e9be902dd4b75deed6,
            128'hf8d2129145ab1599f2e3c6243a65c8e6,
            128'h61f50388fa83d9c7b395a330462025de,
            128'h178ad855b5cad48ff262b8350428cf38,
            128'h0e30987099303ecda0924d5c497e71c2,
            128'h327bf6327901749a66c612d738d5a08e},
            // Y
            {128'h24430b3b5ab1664889282cce6ced5371,
            128'h759161c48bf8ad7f92cd5adf9fe01ea0,
            128'h6ab83b0a51902758e171cc20e8650683,
            128'h89883f6c3d3f23c54292a8fec71210ed,
            128'h9a51a1e5db23c1751d1f7b7dd777220b,
            128'h9cf4b68eb9cbdb8c3e48a59456dd8554,
            128'h51908234c19b268a34e9f85a810af6d7,
            128'h4126744056963a06708214260a7a38c7,
            128'h407d202743fec69da269d196495be4bb,
            128'h37cce16df3342871c272d0c128986e54,
            128'h23aa7e5efcaed9e9be902dd4b75deed6,
            128'hf8d2129145ab1599f2e3c6243a65c8e6,
            128'h61f50388fa83d9c7b395a330462025de,
            128'h178ad855b5cad48ff262b8350428cf38,
            128'h0e30987099303ecda0924d5c497e71c2,
            128'h327bf6327901749a66c612d738d5a08e},
            // M
            {128'h6b1b79941027da82fb14fb54526bdf38,
            128'h4a2de68307ac672f4d057e4b94f49b30,
            128'hede3cecbf038e5b76046cabf282bf737,
            128'hdfdcc073ab91710b006a6c25f3276fe4,
            128'hf1db33c0f015ec44975250947776c460,
            128'h99c676c5fda1dc8e29c61287d0b6a522,
            128'hc36199c62d6d99af15bee67eacd396ac,
            128'ha38889f3b27389b141192961715aa2e2,
            128'hf4d32de3c19c72cc34a0ec37dcc50ddc,
            128'hce49ec1cdc93d866dee0cd0232fdbffa,
            128'h32e0ee9605dcc4327b1fa509fbaa33a1,
            128'hdb9583388ff05441c7ff63cafde5c9e7,
            128'h9dfdadfe69c797724ce2090a0399caf8,
            128'hc53abd386bbf105e65a4e0af403ff9b6,
            128'hb67c7b2ee4fbbabe8078fca28457f1a7,
            128'he23181ed99af0867b019386433a71375},
            // M'_0 = -M^-1 mod 2^W
            128'h75b9f02ac25e3820a0bcfc44104f1b23,
            // expected Z = X * Y * 2^-2048 mod M
            {128'h61b250b41bbdda558e3c9d2c4d52f4ba,
            128'ha1a855af21e2bb166c62497919be0fd5,
            128'h77c388c5aa05c8e0f2d808a8a219e3d5,
            128'h978720d32090eb96b96bd7f3d4e2c5f3,
            128'hf0d57b6d9e0664b0710163ffacbdc395,
            128'hd842d19044354bc2c291d346929e25bb,
            128'h1a4a470d803a10d16be0a0c4f1142e17,
            128'hc358f7cb90a148d092e425acce34189b,
            128'h5369dd381c3db4e5de6b0403f27c89fc,
            128'h3c797cce80a91befb191422571a955e0,
            128'h78766155db324976af8c9ca75c94fadf,
            128'h3927733fc47b2f70db554f0d0d27dba7,
            128'h6f569e0102dbf5f8cb2070292ac71968,
            128'he6e30632927c54692880efcb1a5fbdf3,
            128'he4320931c03d115a490430c15dffefac,
            128'hab6fcb69e53856c5a89d290f3201dc32},
            1'b0, SMM_CYCLES);

        if (errors == 0)
            $display("RESULT: PASS  (%0d of %0d tests, N = 2048)", tests, tests);
        else
            $display("RESULT: FAIL  (%0d of %0d tests failed, N = 2048)", errors, tests);
        $finish;
    end

    // watchdog
    initial begin
        #10000000;
        $display("RESULT: FAIL  (timeout)");
        $finish;
    end
endmodule
