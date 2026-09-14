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

module dag_tb
  import base_pkg::*;
  import math_pkg::*;
  import protocol_pkg::*;
  import system_pkg::*;
;
  logic clk = 0;
  logic rst_n = 0;
  logic valid_in = 0;
  packet_t packet_in;
  logic valid_out;
  packet_t packet_out;

  dag_encoder dut (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_in),
    .packet_in(packet_in),
    .valid_out(valid_out),
    .packet_out(packet_out)
  );

  always #5 clk = ~clk;

  initial begin
    #20;
    rst_n = 1;
    #10;

    // Drive inputs on negedge to ensure clean setup before posedge
    @(negedge clk);
    valid_in = 1'b1;
    packet_in.header.src = 8'h0A;
    packet_in.header.dst = 8'h0B;
    packet_in.header.status = STATUS_OK;
    packet_in.header.reserved = '0;
    packet_in.payload = 16'sd100;

    @(posedge clk);
    #1;
    // Expect output valid_out = 1 and payload = 50 (scaled by 1 bit shift)
    if (!valid_out) begin
      $fatal(1, "[dag_tb] FAIL: Expected valid_out high");
    end
    if (packet_out.header.src != 8'h0A || packet_out.header.dst != 8'h0B) begin
      $fatal(1, "[dag_tb] FAIL: Header addresses mismatched");
    end
    if (packet_out.payload != 16'sd50) begin
      $fatal(1, "[dag_tb] FAIL: Expected payload 50, got %0d", packet_out.payload);
    end

    @(negedge clk);
    valid_in = 1'b0;

    @(posedge clk);
    #1;
    if (valid_out) begin
      $fatal(1, "[dag_tb] FAIL: Expected valid_out to drop low");
    end

    $display("[dag_tb] SUCCESS: Diamond DAG package test passed!");
    $finish;
  end
endmodule
