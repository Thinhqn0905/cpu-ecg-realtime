# Claim Integrity Contract

Mandatory for reports, checklist completion, and user-facing claims. Read
together with `evidence_contract.md`. This contract does not introduce
additional permission requirements for authorized work.

1. Every quantitative claim names metric/unit, run ID, source fingerprint,
   workload, boundary, measurement interval, raw artifact and locator.
2. Missing evidence is `NOT_VERIFIED` or unknown (`null` plus reason),
   never a fabricated zero or borrowed result.
3. Checklists, filenames, RTL comments and PASS labels are not independent
   evidence. Inspect exit status, raw failures and result census.
4. Do not promote simulation to board, synthesis to routed, UART echo to
   ECG streaming, or SPI loopback to AFE communication.
5. Never transfer results between source revisions, FPGA parts, clock
   frequencies, AFE chips, or firmware versions without matched validation.
6. Distinguish `measured`, `simulated`, `synthesized`, `estimated` and
   `source_reported`. Simulation cycle count is not board latency. Nominal
   frequency is derived, not measured.
7. Filelist inclusion does not establish instantiation or resource mapping.
   Use elaborated hierarchy and synthesis reports.
8. Board ECG streaming requires both captured output data compared with
   known input and a correctly bounded timing measurement. UART bytes
   alone are insufficient — verify data content matches expected samples.
9. Never generate, repair or replace captured board outputs from simulation
   data. Keep simulation vectors distinct from board captures.
10. Preserve mismatch, overflow, timeout, synthesis failure and timing
    violation artifacts. Do not rewrite historical failures as PASS.
11. SPI communication proof requires both correct data read AND timing
    compliance. A device ID match alone does not prove reliable operation.
12. Real-time claims require sample rate, channel count, end-to-end latency,
    and continuous duration. A single successful read is not streaming proof.
13. Source suspicions are hypotheses. Root cause requires a measurement or
    controlled experiment; state unresolved contributions explicitly.
14. Recheck terminal results before reporting. A vanished process is not
    evidence of success.
15. Correct inaccurate claims with a dated correction and supporting evidence.
    Preserve unique prior evidence; identify superseded text.
16. User authorization persists. These rules must not be used to invent
    repeated approval flows.

## Boundary Wording

- `simulation`: cycles/behavior observed by a named testbench
- `synthesis`: mapped resources for the specified top module and part
- `routed`: completed routing with complete setup/hold census
- `board`: exact bitstream, programming transcript, captured I/O
- `NOT_VERIFIED`: absent or incompatible evidence
- `FAIL`: observed violation
- `running`: no terminal result yet
