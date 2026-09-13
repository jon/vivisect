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

module ordering_tb;
  import ordering_pkg::*;

  logic clk = 0;
  logic rst_n = 0;

  always #5 clk = ~clk;

  ordering_if bus_inst();

  ordering_dut dut (
    .clk(clk),
    .rst_n(rst_n),
    .bus(bus_inst.consumer)
  );

  initial begin
    #20;
    rst_n = 1;
    bus_inst.msg.payload = 16'hABCD;
    bus_inst.msg.valid = 1'b1;

    @(posedge clk);
    @(posedge clk);

    if (!bus_inst.ack) begin
      $display("FAIL: expected ack to be asserted");
      $fatal(1, "Ordering testbench assertion failed: bus_inst.ack was not asserted");
    end

    $display("PASS: ordering_tb passed successfully");
    $finish;
  end
endmodule
