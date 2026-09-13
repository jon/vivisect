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

module ooo_module (
  input  logic       clk,
  input  logic       rst_n,
  input  logic [7:0] in_val,
  output logic [7:0] out_val
);
  import ooo_pkg::*;

  ooo_data_t r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r.data  <= 8'h00;
      r.valid <= 1'b0;
    end else begin
      r.data  <= in_val;
      r.valid <= OOO_FLAG;
    end
  end

  assign out_val = r.valid ? r.data : 8'h00;
endmodule
