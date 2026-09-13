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

// Self-checking SystemVerilog testbench for counter under AMD xsim.
module counter_tb;
  logic clk = 0;
  logic rst_n = 0;
  logic en = 0;
  logic [7:0] count;

  counter #(.WIDTH(8)) dut (
      .clk(clk),
      .rst_n(rst_n),
      .en(en),
      .count(count)
  );

  // Generate 100MHz clock (10ns period)
  always #5 clk = ~clk;

  initial begin
`ifdef VERILATOR
    $display("[counter_tb] Starting simulation under Verilator...");
`else
    $display("[counter_tb] Starting simulation under AMD xsim...");
`endif

    // Assert reset
    #20;
    rst_n = 1;
    #10;

    // Verify counter is zero while disabled
    en = 0;
    #30;
    if (count != 8'd0) begin
      $fatal(1, "[counter_tb] FAILED: Count was %0d while disabled, expected 0", count);
    end

    // Enable counter for 10 clock cycles
    en = 1;
    #100;
    en = 0;
    #10;

    $display("[counter_tb] Count after 10 cycles: %0d", count);
    if (count != 8'd10) begin
      $fatal(1, "[counter_tb] FAILED: Expected count 10, got %0d", count);
    end

    // Verify asynchronous reset
    rst_n = 0;
    #1;
    if (count != 8'd0) begin
      $fatal(1, "[counter_tb] FAILED: Asynchronous reset failed to clear count");
    end

`ifdef VERILATOR
    $display("[counter_tb] SUCCESS: All counter checks passed under Verilator!");
`else
    $display("[counter_tb] SUCCESS: All counter checks passed under AMD xsim!");
`endif
    $finish;
  end

endmodule
