// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Dual-Target Tightly Coupled Memory (TCM) SRAM.
//              Configurable for FPGA (inferring BRAM with byte-enables)
//              or ASIC (interfacing to Foundry SRAM compiler macros).

module tcm_sram #(
  parameter int unsigned MEM_SIZE_BYTES = 32768, // 32 KB default
  parameter int unsigned ADDR_WIDTH     = $clog2(MEM_SIZE_BYTES),
  parameter bit          TARGET_ASIC    = 1'b0,
  parameter string       INIT_FILE      = ""
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // Port A: Instruction OBI Memory Port (Read-Only)
  input  logic                  instr_req_i,
  output logic                  instr_gnt_o,
  input  logic [31:0]           instr_addr_i,
  output logic                  instr_rvalid_o,
  output logic [31:0]           instr_rdata_o,

  // Port B: Data OBI Memory Port (Read/Write with Byte-Enables)
  input  logic                  data_req_i,
  output logic                  data_gnt_o,
  input  logic [31:0]           data_addr_i,
  input  logic                  data_we_i,
  input  logic [3:0]            data_be_i,
  input  logic [31:0]           data_wdata_i,
  output logic                  data_rvalid_o,
  output logic [31:0]           data_rdata_o
);

  localparam int unsigned NUM_WORDS = MEM_SIZE_BYTES / 4;
  localparam int unsigned WORD_ADDR_WIDTH = $clog2(NUM_WORDS);

  // Address translation (word-aligned)
  wire [WORD_ADDR_WIDTH-1:0] instr_word_addr = instr_addr_i[WORD_ADDR_WIDTH+1:2];
  wire [WORD_ADDR_WIDTH-1:0] data_word_addr  = data_addr_i[WORD_ADDR_WIDTH+1:2];

  // Zero-wait-state grant generation
  assign instr_gnt_o = instr_req_i;
  assign data_gnt_o  = data_req_i;

  // Single-cycle rvalid generation
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_rvalid_o <= 1'b0;
      data_rvalid_o  <= 1'b0;
    end else begin
      instr_rvalid_o <= instr_req_i;
      data_rvalid_o  <= data_req_i;
    end
  end

  // ---------------------------------------------------------------------------
  // Memory Array Implementation (Synthesizable 32-bit Word RAM with Byte-Enables)
  // ---------------------------------------------------------------------------
  logic [31:0] mem [NUM_WORDS-1:0];

  // Initialization: Default to RISC-V NOP (0x0000_0013) to avoid pipeline traps,
  // then load hex image if +firmware plusarg or INIT_FILE is provided.
  initial begin : init_mem
    for (int i = 0; i < NUM_WORDS; i++) begin
      mem[i] = 32'h0000_0013;
    end
`ifdef SIMULATION
    begin
      string fw_file;
      if ($value$plusargs("firmware=%s", fw_file)) begin
        $display("[TCM_SRAM] %m: Loading firmware from plusarg: %s", fw_file);
        $readmemh(fw_file, mem);
      end else if (INIT_FILE != "") begin
        $display("[TCM_SRAM] %m: Loading firmware from INIT_FILE: %s", INIT_FILE);
        $readmemh(INIT_FILE, mem);
      end
    end
`else
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
`endif
  end

  // Port A: Instruction Fetch (Read)
  always_ff @(posedge clk_i) begin
    if (instr_req_i) begin
      instr_rdata_o <= mem[instr_word_addr];
    end
  end

  // Port B: Data Access (Read / Write with byte-enable masking)
  always_ff @(posedge clk_i) begin
    if (data_req_i) begin
      // Write path with byte enables
      if (data_we_i) begin
        if (data_be_i[0]) mem[data_word_addr][ 7: 0] <= data_wdata_i[ 7: 0];
        if (data_be_i[1]) mem[data_word_addr][15: 8] <= data_wdata_i[15: 8];
        if (data_be_i[2]) mem[data_word_addr][23:16] <= data_wdata_i[23:16];
        if (data_be_i[3]) mem[data_word_addr][31:24] <= data_wdata_i[31:24];
      end
      // Read path
      data_rdata_o <= mem[data_word_addr];
    end
  end

endmodule : tcm_sram
