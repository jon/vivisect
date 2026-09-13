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

module ooo_tb;
  logic clk = 0;
  logic rst_n = 0;
  logic [7:0] in_val = 8'h00;
  logic [7:0] out_val;

  always #5 clk <= ~clk;

  ooo_module dut (
    .clk(clk),
    .rst_n(rst_n),
    .in_val(in_val),
    .out_val(out_val)
  );

  initial begin
    #20;
    rst_n = 1;
    in_val = 8'h42;
    @(posedge clk);
    @(posedge clk);
    if (out_val !== 8'h42) begin
      $display("FAIL: expected 8'h42, got %h", out_val);
      $fatal(1, "ooo_tb failure");
    end
    $display("PASS: ooo_tb passed successfully");
    $finish;
  end
endmodule
