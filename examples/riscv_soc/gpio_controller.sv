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

module gpio_controller (
  input  logic        clk,
  input  logic        rst_n,

  // Bus interface
  input  logic        req,
  input  logic        we,
  input  logic [3:0]  be,
  input  logic [3:0]  addr_offset, // Lower address bits
  input  logic [31:0] wdata,
  output logic [31:0] rdata,

  // External IO
  output logic [7:0]  leds,
  input  logic [3:0]  buttons
);

  logic [7:0] led_reg;
  logic [3:0] btn_sync1;
  logic [3:0] btn_sync2;

  // Button synchronizer
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      btn_sync1 <= '0;
      btn_sync2 <= '0;
    end else begin
      btn_sync1 <= buttons;
      btn_sync2 <= btn_sync1;
    end
  end

  assign leds = led_reg;

  // Bus write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      led_reg <= 8'h00;
    end else begin
      if (req && we && (addr_offset == 4'h0)) begin
        if (be[0]) led_reg <= wdata[7:0];
      end
    end
  end

  // Combinational read
  always_comb begin
    case (addr_offset)
      4'h0:    rdata = {24'd0, led_reg};
      4'h4:    rdata = {28'd0, btn_sync2};
      default: rdata = 32'd0;
    endcase
  end

endmodule
