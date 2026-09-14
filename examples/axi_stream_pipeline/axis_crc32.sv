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

// Streaming CRC32 Generator for AXI4-Stream
// Computes Ethernet polynomial 0xEDB88320 over 32-bit words
module axis_crc32 #(
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

  // Master interface (forwards data + appends CRC word at end of packet)
  output logic                  m_axis_tvalid,
  input  logic                  m_axis_tready,
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
  output logic                  m_axis_tlast
);

  localparam logic [31:0] CRC_INIT = 32'hFFFF_FFFF;
  localparam logic [31:0] POLYNOMIAL = 32'hEDB8_8320;

  function automatic [31:0] next_crc32(input [31:0] current_crc, input [31:0] data_word);
    logic [31:0] c;
    c = current_crc ^ data_word;
    for (int i = 0; i < 32; i++) begin
      if (c[0]) begin
        c = (c >> 1) ^ POLYNOMIAL;
      end else begin
        c = (c >> 1);
      end
    end
    return c;
  endfunction

  typedef enum logic [1:0] {
    ST_FORWARD = 2'b00,
    ST_EMIT_CRC = 2'b01
  } state_t;

  state_t state;
  logic [31:0] crc_reg;
  logic [31:0] next_crc;

  always_comb begin
    next_crc = next_crc32(crc_reg, s_axis_tdata);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= ST_FORWARD;
      crc_reg <= CRC_INIT;
    end else begin
      case (state)
        ST_FORWARD: begin
          if (s_axis_tvalid && s_axis_tready) begin
            crc_reg <= next_crc;
            if (s_axis_tlast) begin
              state <= ST_EMIT_CRC;
            end
          end
        end
        ST_EMIT_CRC: begin
          if (m_axis_tready) begin
            crc_reg <= CRC_INIT;
            state   <= ST_FORWARD;
          end
        end
        default: state <= ST_FORWARD;
      endcase
    end
  end

  // Ready to accept input when in FORWARD state and downstream is ready
  assign s_axis_tready = (state == ST_FORWARD) && m_axis_tready;

  // Master output mux
  always_comb begin
    if (state == ST_EMIT_CRC) begin
      m_axis_tvalid = 1'b1;
      m_axis_tdata  = ~crc_reg; // Inverted CRC
      m_axis_tkeep  = 4'b1111;
      m_axis_tlast  = 1'b1;
    end else begin
      m_axis_tvalid = s_axis_tvalid && (state == ST_FORWARD);
      m_axis_tdata  = s_axis_tdata;
      m_axis_tkeep  = s_axis_tkeep;
      m_axis_tlast  = 1'b0; // Suppress tlast from payload; emitted with CRC word
    end
  end

endmodule
