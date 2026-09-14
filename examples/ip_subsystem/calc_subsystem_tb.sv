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

module calc_subsystem_tb;

  logic       clk = 0;
  logic       rst_n = 0;
  always #5 clk <= ~clk;

  logic       valid_in = 0;
  logic [7:0] op_a = '0;
  logic [7:0] op_b = '0;

  wire        valid_out;
  wire  [7:0] result;
  wire  [7:0] accum;

  calc_subsystem dut (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_in),
    .op_a(op_a),
    .op_b(op_b),
    .valid_out(valid_out),
    .result(result),
    .accum(accum)
  );

  initial begin
    #150; // Allow Unisims GSR (active for first 100ns) to deassert
    @(negedge clk);
    rst_n = 1;

    // Vector 1: 15 + 25 = 40 (accum = 40)
    @(negedge clk);
    valid_in = 1;
    op_a     = 8'd15;
    op_b     = 8'd25;

    // Vector 2: 50 + 20 = 70 (accum = 110)
    @(negedge clk);
    valid_in = 1;
    op_a     = 8'd50;
    op_b     = 8'd20;

    // Vector 3: 10 + 5 = 15 (accum = 125)
    @(negedge clk);
    valid_in = 1;
    op_a     = 8'd10;
    op_b     = 8'd5;

    @(negedge clk);
    valid_in = 0;

    // Wait for pipeline outputs (latency is 2 cycles total: 1 in IP + 1 in subsystem)
    repeat (10) @(posedge clk);

    if (accum !== 8'd125) begin
      $fatal(1, "Accumulator mismatch! Expected 125, got %0d", accum);
    end

    $display("SUCCESS: calc_subsystem IP integration verified with accum=%0d.", accum);
    $finish;
  end

  initial begin
    #50000;
    $fatal(1, "Test timeout in calc_subsystem_tb!");
  end

endmodule
