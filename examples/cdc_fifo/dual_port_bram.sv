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

// Simple Dual-Port RAM inferable as Block RAM (BRAM)
module dual_port_bram #(
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 9
) (
  input  logic                  wclk,
  input  logic                  we,
  input  logic [ADDR_WIDTH-1:0] waddr,
  input  logic [DATA_WIDTH-1:0] wdata,

  input  logic                  rclk,
  input  logic                  re,
  input  logic [ADDR_WIDTH-1:0] raddr,
  output logic [DATA_WIDTH-1:0] rdata
);

  localparam int DEPTH = 1 << ADDR_WIDTH;

  (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge wclk) begin
    if (we) begin
      mem[waddr] <= wdata;
    end
  end

  always_ff @(posedge rclk) begin
    if (re) begin
      rdata <= mem[raddr];
    end
  end

endmodule
