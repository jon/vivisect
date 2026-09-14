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

// Math Subsystem integrating AMD Vivado c_addsub IP Core
module calc_subsystem (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       valid_in,
  input  logic [7:0] op_a,
  input  logic [7:0] op_b,
  output logic       valid_out,
  output logic [7:0] result,
  output logic [7:0] accum
);

  logic [7:0] addsub_s;
  logic       v_d1;

  `ifdef VERILATOR
    addsub_8bit_behavioral u_addsub (
      .CLK(clk),
      .CE(valid_in),
      .A(op_a),
      .B(op_b),
      .S(addsub_s)
    );
  `else
    addsub_8bit u_addsub (
      .CLK(clk),
      .CE(valid_in),
      .A(op_a),
      .B(op_b),
      .S(addsub_s)
    );
  `endif

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      v_d1      <= 1'b0;
      valid_out <= 1'b0;
      result    <= '0;
      accum     <= '0;
    end else begin
      v_d1      <= valid_in;
      valid_out <= v_d1;
      if (v_d1) begin
        result <= addsub_s;
        accum  <= accum + addsub_s;
      end
    end
  end

endmodule
