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

// Top-level AXI4-Stream Packet Processing Pipeline
// Flow: Input Skid Buffer -> Packet Filter -> CRC-32 Appender -> Output Skid Buffer
module axis_pipeline_top #(
  parameter int DATA_WIDTH = 32
) (
  input  logic                  clk,
  input  logic                  rst_n,

  // Slave stream input
  input  logic                  s_axis_tvalid,
  output logic                  s_axis_tready,
  input  logic [DATA_WIDTH-1:0] s_axis_tdata,
  input  logic [DATA_WIDTH/8-1:0] s_axis_tkeep,
  input  logic                  s_axis_tlast,

  // Master stream output
  output logic                  m_axis_tvalid,
  input  logic                  m_axis_tready,
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
  output logic                  m_axis_tlast,

  // Diagnostics
  output logic [31:0]           pass_pkt_count,
  output logic [31:0]           drop_pkt_count
);

  localparam int KEEP_WIDTH = DATA_WIDTH / 8;

  // Interconnect signals: Stage 1 (Skid 1) -> Stage 2 (Filter)
  wire                  s1_valid;
  wire                  s1_ready;
  wire [DATA_WIDTH-1:0] s1_data;
  wire [KEEP_WIDTH-1:0] s1_keep;
  wire                  s1_last;

  // Interconnect signals: Stage 2 (Filter) -> Stage 3 (CRC)
  wire                  s2_valid;
  wire                  s2_ready;
  wire [DATA_WIDTH-1:0] s2_data;
  wire [KEEP_WIDTH-1:0] s2_keep;
  wire                  s2_last;

  // Interconnect signals: Stage 3 (CRC) -> Stage 4 (Skid 2)
  wire                  s3_valid;
  wire                  s3_ready;
  wire [DATA_WIDTH-1:0] s3_data;
  wire [KEEP_WIDTH-1:0] s3_keep;
  wire                  s3_last;

  /* verilator lint_off UNUSEDSIGNAL */
  logic unused_user1;
  logic unused_user2;
  /* verilator lint_on UNUSEDSIGNAL */

  // Stage 1: Input Skid Buffer (breaks input timing paths)
  axis_skid_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .USER_WIDTH(1)
  ) u_input_skid (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tuser(1'b0),
    .m_axis_tvalid(s1_valid),
    .m_axis_tready(s1_ready),
    .m_axis_tdata(s1_data),
    .m_axis_tkeep(s1_keep),
    .m_axis_tlast(s1_last),
    .m_axis_tuser(unused_user1)
  );

  // Stage 2: Packet Filter
  axis_packet_filter #(
    .DATA_WIDTH(DATA_WIDTH)
  ) u_filter (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tvalid(s1_valid),
    .s_axis_tready(s1_ready),
    .s_axis_tdata(s1_data),
    .s_axis_tkeep(s1_keep),
    .s_axis_tlast(s1_last),
    .m_axis_tvalid(s2_valid),
    .m_axis_tready(s2_ready),
    .m_axis_tdata(s2_data),
    .m_axis_tkeep(s2_keep),
    .m_axis_tlast(s2_last),
    .pass_pkt_count(pass_pkt_count),
    .drop_pkt_count(drop_pkt_count)
  );

  // Stage 3: Streaming CRC-32 Appender
  axis_crc32 #(
    .DATA_WIDTH(DATA_WIDTH)
  ) u_crc (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tvalid(s2_valid),
    .s_axis_tready(s2_ready),
    .s_axis_tdata(s2_data),
    .s_axis_tkeep(s2_keep),
    .s_axis_tlast(s2_last),
    .m_axis_tvalid(s3_valid),
    .m_axis_tready(s3_ready),
    .m_axis_tdata(s3_data),
    .m_axis_tkeep(s3_keep),
    .m_axis_tlast(s3_last)
  );

  // Stage 4: Output Skid Buffer (breaks output timing paths)
  axis_skid_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .USER_WIDTH(1)
  ) u_output_skid (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tvalid(s3_valid),
    .s_axis_tready(s3_ready),
    .s_axis_tdata(s3_data),
    .s_axis_tkeep(s3_keep),
    .s_axis_tlast(s3_last),
    .s_axis_tuser(1'b0),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tuser(unused_user2)
  );

endmodule
