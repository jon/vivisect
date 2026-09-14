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

// Packet filter: filters packets based on header byte
// Header byte 0xFF indicates a malformed or drop-tagged packet
module axis_packet_filter #(
  parameter int DATA_WIDTH = 32
) (
  input  logic                  clk,
  input  logic                  rst_n,

  // Slave interface
  input  logic                  s_axis_tvalid,
  output logic                  s_axis_tready,
  input  logic [DATA_WIDTH-1:0] s_axis_tdata,
  input  logic [DATA_WIDTH/8-1:0] s_axis_tkeep,
  input  logic                  s_axis_tlast,

  // Master interface
  output logic                  m_axis_tvalid,
  input  logic                  m_axis_tready,
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
  output logic                  m_axis_tlast,

  // Statistics counters
  output logic [31:0]           pass_pkt_count,
  output logic [31:0]           drop_pkt_count
);

  typedef enum logic [1:0] {
    ST_HEADER = 2'b00,
    ST_PASS   = 2'b01,
    ST_DROP   = 2'b10
  } filter_state_t;

  filter_state_t state;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state          <= ST_HEADER;
      pass_pkt_count <= '0;
      drop_pkt_count <= '0;
    end else begin
      case (state)
        ST_HEADER: begin
          if (s_axis_tvalid && s_axis_tready) begin
            if (s_axis_tdata[31:24] == 8'hFF) begin
              // Drop this packet
              if (s_axis_tlast) begin
                drop_pkt_count <= drop_pkt_count + 1;
                state          <= ST_HEADER;
              end else begin
                state          <= ST_DROP;
              end
            end else begin
              // Pass this packet
              if (s_axis_tlast) begin
                pass_pkt_count <= pass_pkt_count + 1;
                state          <= ST_HEADER;
              end else begin
                state          <= ST_PASS;
              end
            end
          end
        end

        ST_PASS: begin
          if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
            pass_pkt_count <= pass_pkt_count + 1;
            state          <= ST_HEADER;
          end
        end

        ST_DROP: begin
          if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
            drop_pkt_count <= drop_pkt_count + 1;
            state          <= ST_HEADER;
          end
        end

        default: state <= ST_HEADER;
      endcase
    end
  end

  // Ready generation
  assign s_axis_tready = (state == ST_DROP) ? 1'b1 : m_axis_tready;

  // Master output
  always_comb begin
    if (state == ST_DROP) begin
      m_axis_tvalid = 1'b0;
      m_axis_tdata  = '0;
      m_axis_tkeep  = '0;
      m_axis_tlast  = 1'b0;
    end else if (state == ST_HEADER && s_axis_tvalid && (s_axis_tdata[31:24] == 8'hFF)) begin
      // Drop immediately on header beat
      m_axis_tvalid = 1'b0;
      m_axis_tdata  = '0;
      m_axis_tkeep  = '0;
      m_axis_tlast  = 1'b0;
    end else begin
      m_axis_tvalid = s_axis_tvalid;
      m_axis_tdata  = s_axis_tdata;
      m_axis_tkeep  = s_axis_tkeep;
      m_axis_tlast  = s_axis_tlast;
    end
  end

endmodule
