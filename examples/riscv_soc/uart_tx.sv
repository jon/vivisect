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

module uart_tx #(
  parameter int CLKS_PER_BIT = 16
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic [7:0] tx_data,
  input  logic       tx_start,
  output logic       tx_serial,
  output logic       tx_busy
);

  typedef enum logic [1:0] {
    IDLE  = 2'b00,
    START = 2'b01,
    DATA  = 2'b10,
    STOP  = 2'b11
  } uart_state_t;

  uart_state_t state;
  logic [15:0] clk_cnt;
  logic [2:0]  bit_idx;
  logic [7:0]  tx_data_reg;

  assign tx_busy = (state != IDLE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= IDLE;
      tx_serial   <= 1'b1;
      clk_cnt     <= '0;
      bit_idx     <= '0;
      tx_data_reg <= '0;
    end else begin
      case (state)
        IDLE: begin
          tx_serial <= 1'b1;
          clk_cnt   <= '0;
          bit_idx   <= '0;
          if (tx_start) begin
            tx_data_reg <= tx_data;
            state       <= START;
          end
        end

        START: begin
          tx_serial <= 1'b0; // Start bit
          if (clk_cnt < 16'(CLKS_PER_BIT - 1)) begin
            clk_cnt <= clk_cnt + 1;
          end else begin
            clk_cnt <= '0;
            state   <= DATA;
          end
        end

        DATA: begin
          tx_serial <= tx_data_reg[bit_idx];
          if (clk_cnt < 16'(CLKS_PER_BIT - 1)) begin
            clk_cnt <= clk_cnt + 1;
          end else begin
            clk_cnt <= '0;
            if (bit_idx < 3'd7) begin
              bit_idx <= bit_idx + 1;
            end else begin
              bit_idx <= '0;
              state   <= STOP;
            end
          end
        end

        STOP: begin
          tx_serial <= 1'b1; // Stop bit
          if (clk_cnt < 16'(CLKS_PER_BIT - 1)) begin
            clk_cnt <= clk_cnt + 1;
          end else begin
            clk_cnt <= '0;
            state   <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
