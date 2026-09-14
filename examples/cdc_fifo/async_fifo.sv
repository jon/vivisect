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

// Parameterized Dual-Clock Asynchronous FIFO with Gray-Code CDC
module async_fifo #(
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 9,
  parameter int ALMOST_FULL_THRESH = 16,
  parameter int ALMOST_EMPTY_THRESH = 16
) (
  // Write clock domain
  input  logic                  wclk,
  input  logic                  wrst_n,
  input  logic                  winc,
  input  logic [DATA_WIDTH-1:0] wdata,
  output logic                  wfull,
  output logic                  walmost_full,

  // Read clock domain
  input  logic                  rclk,
  input  logic                  rrst_n,
  input  logic                  rinc,
  output logic [DATA_WIDTH-1:0] rdata,
  output logic                  rempty,
  output logic                  ralmost_empty
);

  localparam int PTR_WIDTH = ADDR_WIDTH + 1;
  localparam int DEPTH = 1 << ADDR_WIDTH;

  // Internal pointer registers
  logic [PTR_WIDTH-1:0] wbin;
  logic [PTR_WIDTH-1:0] wgray;
  logic [PTR_WIDTH-1:0] rbin;
  logic [PTR_WIDTH-1:0] rgray;

  // Synchronized Gray pointers
  logic [PTR_WIDTH-1:0] wq2_rgray;
  logic [PTR_WIDTH-1:0] rq2_wgray;

  // Next-state pointer logic
  logic [PTR_WIDTH-1:0] wbin_next;
  logic [PTR_WIDTH-1:0] wgray_next;
  logic [PTR_WIDTH-1:0] rbin_next;
  logic [PTR_WIDTH-1:0] rgray_next;

  logic wfull_val;
  logic rempty_val;

  // Memory write enable
  wire w_en = winc && !wfull;
  wire r_en = rinc && !rempty;

  // Instantiate dual-port memory
  dual_port_bram #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_mem (
    .wclk(wclk),
    .we(w_en),
    .waddr(wbin[ADDR_WIDTH-1:0]),
    .wdata(wdata),
    .rclk(rclk),
    .re(r_en),
    .raddr(rbin[ADDR_WIDTH-1:0]),
    .rdata(rdata)
  );

  // Synchronize rgray into wclk domain
  sync_2ff #(.WIDTH(PTR_WIDTH)) u_sync_r2w (
    .clk(wclk),
    .rst_n(wrst_n),
    .din(rgray),
    .dout(wq2_rgray)
  );

  // Synchronize wgray into rclk domain
  sync_2ff #(.WIDTH(PTR_WIDTH)) u_sync_w2r (
    .clk(rclk),
    .rst_n(rrst_n),
    .din(wgray),
    .dout(rq2_wgray)
  );

  // -------------------------------------------------------------
  // Write Domain Logic
  // -------------------------------------------------------------
  assign wbin_next  = wbin + (w_en ? PTR_WIDTH'(1) : PTR_WIDTH'(0));
  assign wgray_next = (wbin_next >> 1) ^ wbin_next;

  // Full condition: Gray MSB and MSB-1 inverted, remaining bits equal
  assign wfull_val = (wgray_next == {~wq2_rgray[PTR_WIDTH-1:PTR_WIDTH-2], wq2_rgray[PTR_WIDTH-3:0]});

  always_ff @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      wbin   <= '0;
      wgray  <= '0;
      wfull  <= 1'b0;
    end else begin
      wbin   <= wbin_next;
      wgray  <= wgray_next;
      wfull  <= wfull_val;
    end
  end

  // Convert wq2_rgray back to binary for almost_full calculation
  logic [PTR_WIDTH-1:0] wq2_rbin;
  always_comb begin
    wq2_rbin[PTR_WIDTH-1] = wq2_rgray[PTR_WIDTH-1];
    for (int i = PTR_WIDTH - 2; i >= 0; i--) begin
      wq2_rbin[i] = wq2_rbin[i+1] ^ wq2_rgray[i];
    end
  end

  wire [PTR_WIDTH-1:0] w_occupancy = wbin - wq2_rbin;
  always_ff @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      walmost_full <= 1'b0;
    end else begin
      walmost_full <= (w_occupancy >= PTR_WIDTH'(DEPTH - ALMOST_FULL_THRESH));
    end
  end

  // -------------------------------------------------------------
  // Read Domain Logic
  // -------------------------------------------------------------
  assign rbin_next  = rbin + (r_en ? PTR_WIDTH'(1) : PTR_WIDTH'(0));
  assign rgray_next = (rbin_next >> 1) ^ rbin_next;

  assign rempty_val = (rgray_next == rq2_wgray);

  always_ff @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      rbin   <= '0;
      rgray  <= '0;
      rempty <= 1'b1;
    end else begin
      rbin   <= rbin_next;
      rgray  <= rgray_next;
      rempty <= rempty_val;
    end
  end

  // Convert rq2_wgray back to binary for almost_empty calculation
  logic [PTR_WIDTH-1:0] rq2_wbin;
  always_comb begin
    rq2_wbin[PTR_WIDTH-1] = rq2_wgray[PTR_WIDTH-1];
    for (int i = PTR_WIDTH - 2; i >= 0; i--) begin
      rq2_wbin[i] = rq2_wbin[i+1] ^ rq2_wgray[i];
    end
  end

  wire [PTR_WIDTH-1:0] r_occupancy = rq2_wbin - rbin;
  always_ff @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      ralmost_empty <= 1'b1;
    end else begin
      ralmost_empty <= (r_occupancy <= PTR_WIDTH'(ALMOST_EMPTY_THRESH));
    end
  end

endmodule
