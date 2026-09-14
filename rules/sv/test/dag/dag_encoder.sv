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

module dag_encoder
  import base_pkg::*;
  import math_pkg::*;
  import protocol_pkg::*;
  import system_pkg::*;
(
  input  logic       clk,
  input  logic       rst_n,
  input  logic       valid_in,
  input  packet_t    packet_in,
  output logic       valid_out,
  output packet_t    packet_out
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out  <= 1'b0;
      packet_out <= '0;
    end else begin
      valid_out <= valid_in;
      if (valid_in) begin
        packet_out.header.src <= packet_in.header.src;
        packet_out.header.dst <= packet_in.header.dst;
        packet_out.header.reserved <= '0;
        if (packet_in.header.status == STATUS_OK) begin
          packet_out.header.status <= STATUS_OK;
          packet_out.payload <= scale_fixed(packet_in.payload, 2'd1);
        end else begin
          packet_out.header.status <= STATUS_ERR;
          packet_out.payload <= '0;
        end
      end
    end
  end

endmodule
