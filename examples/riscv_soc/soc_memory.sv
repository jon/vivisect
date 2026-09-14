// Copyright 2026 The Vivisect Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`timescale 1ns / 1ps

// Dual-Port/Single-Port Byte-Addressable RAM initialized with firmware
module soc_memory #(
  parameter int WORDS = 2048, // 8KB
  parameter string INIT_FILE = ""
) (
  input  logic        clk,
  input  logic        req,
  input  logic        we,
  input  logic [3:0]  be,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  output logic [31:0] rdata
);

  // 32-bit word memory
  (* ram_style = "block" *) logic [31:0] mem [0:WORDS-1];

  // Word-aligned address index
  wire [$clog2(WORDS)-1:0] word_idx = addr[2 + $clog2(WORDS)-1:2];

  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  always_ff @(posedge clk) begin
    if (req) begin
      if (we) begin
        if (be[0]) mem[word_idx][7:0]   <= wdata[7:0];
        if (be[1]) mem[word_idx][15:8]  <= wdata[15:8];
        if (be[2]) mem[word_idx][23:16] <= wdata[23:16];
        if (be[3]) mem[word_idx][31:24] <= wdata[31:24];
      end
      rdata <= mem[word_idx];
    end
  end

endmodule
