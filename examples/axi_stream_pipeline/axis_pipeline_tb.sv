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

module axis_pipeline_tb;

  localparam int DATA_WIDTH = 32;

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk <= ~clk;

  // Stream slave input
  logic                  s_axis_tvalid = 0;
  wire                   s_axis_tready;
  logic [DATA_WIDTH-1:0] s_axis_tdata = '0;
  logic [3:0]            s_axis_tkeep = 4'b1111;
  logic                  s_axis_tlast = 0;

  // Stream master output
  wire                   m_axis_tvalid;
  logic                  m_axis_tready = 1;
  wire  [DATA_WIDTH-1:0] m_axis_tdata;
  wire  [3:0]            m_axis_tkeep;
  wire                   m_axis_tlast;

  wire  [31:0]           pass_pkt_count;
  wire  [31:0]           drop_pkt_count;

  // DUT instantiation
  axis_pipeline_top #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tlast(m_axis_tlast),
    .pass_pkt_count(pass_pkt_count),
    .drop_pkt_count(drop_pkt_count)
  );

  // Scoreboard tracking
  int rx_packet_count = 0;
  int rx_beat_count = 0;

  // Reset
  initial begin
    #20;
    @(negedge clk);
    rst_n = 1;
  end

  // Task to send a packet
  task automatic send_packet(input bit should_drop, input int len);
    for (int b = 0; b < len; b++) begin
      @(negedge clk);
      s_axis_tvalid <= 1'b1;
      s_axis_tkeep  <= 4'b1111;
      s_axis_tlast  <= (b == len - 1);
      if (b == 0) begin
        // Header beat
        s_axis_tdata <= should_drop ? {8'hFF, 24'h010203} : {8'h10, 24'hAABBCC};
      end else begin
        s_axis_tdata <= 32'hD000_0000 | (b & 32'hFFFF);
      end

      // Wait for handshake
      do begin
        @(posedge clk);
      end while (!s_axis_tready);
    end
    @(negedge clk);
    s_axis_tvalid <= 1'b0;
    s_axis_tlast  <= 1'b0;
  endtask

  // Stimulus driver
  initial begin
    @(posedge rst_n);
    #50;

    // Send 10 passing packets and 5 dropping packets in interleaved order
    for (int p = 0; p < 15; p++) begin
      bit drop = (p % 3 == 2);
      send_packet(drop, 3 + (p % 4));
      // Inter-packet idle gap
      repeat ($urandom_range(1, 4)) @(posedge clk);
    end

    // Wait for pipeline to drain
    repeat (100) @(posedge clk);

    if (pass_pkt_count != 10) begin
      $fatal(1, "Expected 10 passed packets, got %0d", pass_pkt_count);
    end
    if (drop_pkt_count != 5) begin
      $fatal(1, "Expected 5 dropped packets, got %0d", drop_pkt_count);
    end

    $display("SUCCESS: AXI4-Stream Pipeline verified passing 10 packets, dropping 5 packets under backpressure.");
    $finish;
  end

  // Random backpressure receiver
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axis_tready <= 1'b1;
    end else begin
      // Apply random backpressure: 70% ready, 30% stalled
      m_axis_tready <= ($urandom_range(0, 9) < 7);
      if (m_axis_tvalid && m_axis_tready) begin
        rx_beat_count++;
        if (m_axis_tlast) begin
          rx_packet_count++;
        end
      end
    end
  end

  // Watchdog timer
  initial begin
    #200000;
    $fatal(1, "Test timeout in AXI4-Stream Pipeline testbench!");
  end

endmodule
