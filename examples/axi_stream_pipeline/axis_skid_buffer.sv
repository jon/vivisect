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

// Zero-bubble AXI4-Stream Skid Buffer that fully registers both forward and backward paths
module axis_skid_buffer #(
  parameter int DATA_WIDTH = 32,
  parameter int USER_WIDTH = 1
) (
  input  logic                  clk,
  input  logic                  rst_n,

  // Slave interface (input stream)
  input  logic                  s_axis_tvalid,
  output logic                  s_axis_tready,
  input  logic [DATA_WIDTH-1:0] s_axis_tdata,
  input  logic [DATA_WIDTH/8-1:0] s_axis_tkeep,
  input  logic                  s_axis_tlast,
  input  logic [USER_WIDTH-1:0] s_axis_tuser,

  // Master interface (output stream)
  output logic                  m_axis_tvalid,
  input  logic                  m_axis_tready,
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
  output logic                  m_axis_tlast,
  output logic [USER_WIDTH-1:0] m_axis_tuser
);

  localparam int KEEP_WIDTH = DATA_WIDTH / 8;

  // Primary and secondary buffer registers
  logic                  buf_valid;
  logic [DATA_WIDTH-1:0] buf_data;
  logic [KEEP_WIDTH-1:0] buf_keep;
  logic                  buf_last;
  logic [USER_WIDTH-1:0] buf_user;

  logic                  skid_valid;
  logic [DATA_WIDTH-1:0] skid_data;
  logic [KEEP_WIDTH-1:0] skid_keep;
  logic                  skid_last;
  logic [USER_WIDTH-1:0] skid_user;

  // Ready when skid buffer is not occupying the secondary slot
  assign s_axis_tready = !skid_valid;

  // Output drives from primary buffer if valid, else skid buffer
  assign m_axis_tvalid = buf_valid;
  assign m_axis_tdata  = buf_data;
  assign m_axis_tkeep  = buf_keep;
  assign m_axis_tlast  = buf_last;
  assign m_axis_tuser  = buf_user;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      buf_valid  <= 1'b0;
      buf_data   <= '0;
      buf_keep   <= '0;
      buf_last   <= 1'b0;
      buf_user   <= '0;
      skid_valid <= 1'b0;
      skid_data  <= '0;
      skid_keep  <= '0;
      skid_last  <= 1'b0;
      skid_user  <= '0;
    end else begin
      // If downstream accepted data, clear primary buffer
      if (m_axis_tready && buf_valid) begin
        buf_valid <= 1'b0;
      end

      // Process incoming data
      if (s_axis_tvalid && s_axis_tready) begin
        if (!buf_valid || (m_axis_tready && buf_valid)) begin
          // Bypass straight to primary buffer
          buf_valid <= 1'b1;
          buf_data  <= s_axis_tdata;
          buf_keep  <= s_axis_tkeep;
          buf_last  <= s_axis_tlast;
          buf_user  <= s_axis_tuser;
        end else begin
          // Primary buffer full and stalled, store into skid buffer
          skid_valid <= 1'b1;
          skid_data  <= s_axis_tdata;
          skid_keep  <= s_axis_tkeep;
          skid_last  <= s_axis_tlast;
          skid_user  <= s_axis_tuser;
        end
      end else if (m_axis_tready && skid_valid) begin
        // Drain skid buffer into primary buffer
        buf_valid  <= 1'b1;
        buf_data   <= skid_data;
        buf_keep   <= skid_keep;
        buf_last   <= skid_last;
        buf_user   <= skid_user;
        skid_valid <= 1'b0;
      end
    end
  end

endmodule
