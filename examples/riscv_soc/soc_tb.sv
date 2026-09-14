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

module soc_tb;

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk <= ~clk;

  wire        uart_tx_serial;
  wire  [7:0] leds;
  logic [3:0] buttons = 4'b0101;
  wire  [31:0] sim_pass_sig;

  // Resolve path to firmware.mem
  localparam string MEM_FILE = "examples/riscv_soc/firmware.mem";

  riscv_soc_top #(
    .MEM_INIT_FILE(MEM_FILE),
    .CLKS_PER_BIT(8) // Fast UART for simulation
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .uart_tx_serial(uart_tx_serial),
    .leds(leds),
    .buttons(buttons),
    .sim_pass_sig(sim_pass_sig)
  );

  // Reset sequence
  initial begin
    #20;
    @(negedge clk);
    rst_n = 1;
  end

  // Monitor pass signature and verify results
  initial begin
    @(posedge rst_n);
    while (sim_pass_sig !== 32'hDEADBEEF) begin
      @(posedge clk);
    end

    // Verify LED outputs (buttons 0x5 shifted left by 1 and OR'ed with 1 = 0x0B)
    if (leds !== 8'h0B) begin
      $fatal(1, "LED output mismatch! Expected 0x0B, got 0x%02h", leds);
    end

    // Verify Fibonacci(9) stored at memory address 0x100 (word 64 = 34 = 0x22)
    if (dut.u_ram.mem[64] !== 32'd34) begin
      $fatal(1, "RAM Fibonacci result mismatch at 0x100! Expected 34, got %0d", dut.u_ram.mem[64]);
    end

    $display("SUCCESS: RISC-V SoC completed firmware execution and Fibonacci computation (sig=0x%08h, leds=0x%02h, fib(9)=%0d).",
             sim_pass_sig, leds, dut.u_ram.mem[64]);
    $finish;
  end

  // Watchdog timer
  initial begin
    #200000;
    $fatal(1, "Test timeout in RISC-V SoC testbench! sim_pass_sig=0x%08h, pc=0x%08h", sim_pass_sig, dut.core_pc);
  end

endmodule
