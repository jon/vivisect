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

module defines_tb;
  logic clk = 0;
  logic rst_n = 0;
  logic [31:0] out_val;

  defines_mod dut (
    .clk(clk),
    .rst_n(rst_n),
    .out_val(out_val)
  );

  always #5 clk = ~clk;

  initial begin
    #20;
    rst_n = 1;
    #10;
    @(posedge clk);
    #1;

    // Expected value is `DERIVED_VAL which is 32'hCAFE1234 + 1 = 32'hCAFE1235
    if (out_val !== 32'hCAFE1235) begin
      $fatal(1, "[defines_tb] FAIL: Expected out_val = 32'hCAFE1235, got %h", out_val);
    end

    $display("[defines_tb] SUCCESS: Defines and nested includes verified! out_val = %h", out_val);
    $finish;
  end
endmodule
