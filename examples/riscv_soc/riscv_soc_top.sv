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

module riscv_soc_top #(
  parameter string MEM_INIT_FILE = "",
  parameter int CLKS_PER_BIT = 16
) (
  input  logic       clk,
  input  logic       rst_n,

  // Board IO
  output logic       uart_tx_serial,
  output logic [7:0] leds,
  input  logic [3:0] buttons,

  // Simulation status indicator
  output logic [31:0] sim_pass_sig
);

  // Core memory interface
  wire [31:0] core_addr;
  wire [31:0] core_wdata;
  wire [3:0]  core_be;
  wire        core_we;
  wire        core_req;
  logic [31:0] core_rdata;
  wire [31:0] core_pc;

  // Peripheral select decodes
  wire is_ram  = (core_addr < 32'h0001_0000);
  wire is_gpio = (core_addr[31:4] == 28'h8000000); // 0x8000_0000 - 0x8000_000F
  wire is_uart = (core_addr[31:4] == 28'h8000001); // 0x8000_0010 - 0x8000_001F
  wire is_pass = (core_addr == 32'h8000_0020);

  // Clock divider: 100 MHz board clock -> 25 MHz system clock
  logic [1:0] clk_div = '0;
  always_ff @(posedge clk) begin
    clk_div <= clk_div + 1'b1;
  end

`ifdef SYNTHESIS
  wire sys_clk;
  BUFG u_clk_bufg (
    .I(clk_div[1]),
    .O(sys_clk)
  );
`else
  wire sys_clk = clk_div[1];
`endif

  // RAM read data
  wire [31:0] ram_rdata;
  wire [31:0] gpio_rdata;
  logic [31:0] uart_rdata;

  // Internal power-on reset generator
  logic [7:0] por_cnt = '0;
  logic sys_rst_n = 1'b0;
  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused_rst_n = rst_n;
  /* verilator lint_on UNUSEDSIGNAL */

  always_ff @(posedge sys_clk) begin
    if (por_cnt != 8'hFF) begin
      por_cnt   <= por_cnt + 1'b1;
      sys_rst_n <= 1'b0;
    end else begin
      sys_rst_n <= 1'b1;
    end
  end

  // UART TX control
  logic [7:0] uart_tx_byte;
  logic       uart_tx_start;
  wire        uart_tx_busy;

  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      uart_tx_start <= 1'b0;
      uart_tx_byte  <= '0;
      sim_pass_sig  <= '0;
    end else begin
      uart_tx_start <= 1'b0;
      if (core_req && core_we) begin
        if (is_uart && (core_addr[3:0] == 4'h0)) begin
          uart_tx_byte  <= core_wdata[7:0];
          uart_tx_start <= 1'b1;
        end
        if (is_pass) begin
          sim_pass_sig <= core_wdata;
        end
      end
    end
  end


  assign uart_rdata = {31'd0, uart_tx_busy};

  // Bus response mux
  always_comb begin
    if (is_ram) begin
      core_rdata = ram_rdata;
    end else if (is_gpio) begin
      core_rdata = gpio_rdata;
    end else if (is_uart) begin
      core_rdata = uart_rdata;
    end else begin
      core_rdata = 32'h0000_0000;
    end
  end

  // 1. CPU Core
  rv32i_core u_cpu (
    .clk(sys_clk),
    .rst_n(sys_rst_n),
    .mem_addr(core_addr),
    .mem_wdata(core_wdata),
    .mem_be(core_be),
    .mem_we(core_we),
    .mem_req(core_req),
    .mem_rdata(core_rdata),
    .pc_out(core_pc)
  );

  // 2. RAM
  soc_memory #(
    .WORDS(2048),
    .INIT_FILE(MEM_INIT_FILE)
  ) u_ram (
    .clk(sys_clk),
    .req(core_req && is_ram),
    .we(core_we),
    .be(core_be),
    .addr(core_addr),
    .wdata(core_wdata),
    .rdata(ram_rdata)
  );

  // 3. GPIO Controller
  gpio_controller u_gpio (
    .clk(sys_clk),
    .rst_n(sys_rst_n),
    .req(core_req && is_gpio),
    .we(core_we),
    .be(core_be),
    .addr_offset(core_addr[3:0]),
    .wdata(core_wdata),
    .rdata(gpio_rdata),
    .leds(leds),
    .buttons(buttons)
  );

  // 4. UART TX
  uart_tx #(
    .CLKS_PER_BIT(CLKS_PER_BIT)
  ) u_uart (
    .clk(sys_clk),
    .rst_n(sys_rst_n),
    .tx_data(uart_tx_byte),
    .tx_start(uart_tx_start),
    .tx_serial(uart_tx_serial),
    .tx_busy(uart_tx_busy)
  );

endmodule
