# Fault-Resilient FLALM: Arithmetic Consistency Checking and Recovery for Karatsuba-Based Montgomery Modular Multiplication

Montgomery modular multiplication is widely used
in public-key cryptography, where faults in arithmetic computa-
tions can compromise the correctness of cryptographic results.
The Flexible Low Area-Latency Montgomery Modular Multi-
plication (FLALM) architecture reduces hardware cost through
resource sharing and Karatsuba-based multiplication. However,
corruption of a stored intermediate product can propagate
through subsequent operations and affect the final modular
result. This paper presents a fault-resilient extension of FLALM
that integrates two arithmetic consistency monitors with bounded
transaction recovery without duplicating the complete multiplier.
The monitors operate modulo 8191 and verify the reconstructed
Karatsuba product and the upper partial product respectively.
A detected inconsistency triggers one re-execution attempt,
while repeated detection prevents successful result acceptance.
Across 7,680 RTL fault-injection experiments targeting three
intermediate-product states, 7,296 injections corrupted the initial
computation and all were detected and recovered. The remaining
384 disturbances were detected without changing the initial
result. No silent data corruption was observed in this campaign. A
separate targeted evaluation of 227 residue-preserving correlated
faults produced 203 undetected result corruptions, exposing
a limitation of finite-residue checking. On a Xilinx Kintex
UltraScale+ FPGA, the protected implementation incurs 36.03%
LUT, 14.40% flip-flop, and 12.50% DSP overhead. The routed
critical-path delay increases by 31.92%. Estimated maximum
operating frequency decreases by 22.91%, while vectorless total-
power estimates remain nearly unchanged. These results quantify
the detection capability, recovery behavior and implementation
trade-offs of arithmetic-aware protection in a resource-shared
Montgomery multiplier. 
