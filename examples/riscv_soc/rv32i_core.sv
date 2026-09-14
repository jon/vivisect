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

/* verilator lint_off IMPORTSTAR */
import rv32i_pkg::*;
/* verilator lint_on IMPORTSTAR */

module rv32i_core (
  input  logic        clk,
  input  logic        rst_n,

  // Memory interface (shared instruction & data bus)
  output logic [31:0] mem_addr,
  output logic [31:0] mem_wdata,
  output logic [3:0]  mem_be,
  output logic        mem_we,
  output logic        mem_req,
  input  logic [31:0] mem_rdata,

  // Status / debug
  output logic [31:0] pc_out
);

  // States
  typedef enum logic [2:0] {
    ST_FETCH        = 3'b000,
    ST_FETCH_WAIT   = 3'b001,
    ST_EXEC         = 3'b010,
    ST_STORE_WAIT   = 3'b011,
    ST_LOAD_WAIT    = 3'b100,
    ST_LOAD_CAPTURE = 3'b101
  } state_t;

  state_t state;

  // Program Counter
  logic [31:0] pc;
  logic [31:0] instr_reg;
  wire  [31:0] instr = (state == ST_EXEC) ? mem_rdata : instr_reg;

  assign pc_out = pc;

  // Register File: 32 x 32-bit registers
  logic [31:0] regfile [0:31];
  wire  [4:0]  rs1_idx = instr[19:15];
  wire  [4:0]  rs2_idx = instr[24:20];
  wire  [4:0]  rd_idx  = instr[11:7];
  wire  [6:0]  opcode  = instr[6:0];
  wire  [2:0]  funct3  = instr[14:12];
  wire  [6:0]  funct7  = instr[31:25];

  // Register reads (x0 is always 0)
  wire [31:0] rs1_data = (rs1_idx == 5'd0) ? 32'd0 : regfile[rs1_idx];
  wire [31:0] rs2_data = (rs2_idx == 5'd0) ? 32'd0 : regfile[rs2_idx];

  // Immediate decoding
  wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
  wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  wire [31:0] imm_u = {instr[31:12], 12'b0};
  wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

  // ALU operands
  logic [31:0] alu_op1;
  logic [31:0] alu_op2;
  logic [31:0] alu_result;

  always_comb begin
    case (opcode)
      OP_LUI:   alu_op1 = 32'd0;
      OP_AUIPC: alu_op1 = pc;
      OP_JAL:   alu_op1 = pc;
      OP_JALR:  alu_op1 = pc;
      default:  alu_op1 = rs1_data;
    endcase
  end

  always_comb begin
    case (opcode)
      OP_OP_IMM: alu_op2 = imm_i;
      OP_LUI:    alu_op2 = imm_u;
      OP_AUIPC:  alu_op2 = imm_u;
      OP_JAL:    alu_op2 = 32'd4;
      OP_JALR:   alu_op2 = 32'd4;
      default:   alu_op2 = rs2_data;
    endcase
  end

  // ALU operation
  always_comb begin
    case (opcode)
      OP_LUI, OP_AUIPC, OP_JAL, OP_JALR: alu_result = alu_op1 + alu_op2;
      OP_OP_IMM: begin
        case (funct3)
          3'b000: alu_result = alu_op1 + alu_op2; // ADDI
          3'b010: alu_result = ($signed(alu_op1) < $signed(alu_op2)) ? 32'd1 : 32'd0; // SLTI
          3'b011: alu_result = (alu_op1 < alu_op2) ? 32'd1 : 32'd0; // SLTIU
          3'b100: alu_result = alu_op1 ^ alu_op2; // XORI
          3'b110: alu_result = alu_op1 | alu_op2; // ORI
          3'b111: alu_result = alu_op1 & alu_op2; // ANDI
          3'b001: alu_result = alu_op1 << alu_op2[4:0]; // SLLI
          3'b101: alu_result = funct7[5] ? ($signed(alu_op1) >>> alu_op2[4:0]) : (alu_op1 >> alu_op2[4:0]); // SRAI / SRLI
          default: alu_result = 32'd0;
        endcase
      end
      OP_OP: begin
        case (funct3)
          3'b000: alu_result = funct7[5] ? (alu_op1 - alu_op2) : (alu_op1 + alu_op2); // SUB / ADD
          3'b001: alu_result = alu_op1 << alu_op2[4:0]; // SLL
          3'b010: alu_result = ($signed(alu_op1) < $signed(alu_op2)) ? 32'd1 : 32'd0; // SLT
          3'b011: alu_result = (alu_op1 < alu_op2) ? 32'd1 : 32'd0; // SLTU
          3'b100: alu_result = alu_op1 ^ alu_op2; // XOR
          3'b101: alu_result = funct7[5] ? ($signed(alu_op1) >>> alu_op2[4:0]) : (alu_op1 >> alu_op2[4:0]); // SRA / SRL
          3'b110: alu_result = alu_op1 | alu_op2; // OR
          3'b111: alu_result = alu_op1 & alu_op2; // AND
          default: alu_result = 32'd0;
        endcase
      end
      default: alu_result = alu_op1 + alu_op2;
    endcase
  end

  // Branch condition evaluation
  logic branch_taken;
  always_comb begin
    case (funct3)
      BR_BEQ:  branch_taken = (rs1_data == rs2_data);
      BR_BNE:  branch_taken = (rs1_data != rs2_data);
      BR_BLT:  branch_taken = ($signed(rs1_data) < $signed(rs2_data));
      BR_BGE:  branch_taken = ($signed(rs1_data) >= $signed(rs2_data));
      BR_BLTU: branch_taken = (rs1_data < rs2_data);
      BR_BGEU: branch_taken = (rs1_data >= rs2_data);
      default: branch_taken = 1'b0;
    endcase
  end

  // FSM and CPU execution
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= ST_FETCH;
      pc        <= 32'd0;
      instr_reg <= 32'd0;
      mem_req   <= 1'b0;
      mem_we    <= 1'b0;
      mem_be    <= 4'b0000;
      mem_addr  <= 32'd0;
      mem_wdata <= 32'd0;
      for (int i = 0; i < 32; i++) begin
        regfile[i] <= 32'd0;
      end
    end else begin
      case (state)
        ST_FETCH: begin
          // Issue instruction fetch
          mem_addr  <= pc;
          mem_req   <= 1'b1;
          mem_we    <= 1'b0;
          mem_be    <= 4'b1111;
          state     <= ST_FETCH_WAIT;
        end

        ST_FETCH_WAIT: begin
          mem_req <= 1'b0;
          state   <= ST_EXEC;
        end

        ST_EXEC: begin
          instr_reg <= mem_rdata;
          case (opcode)
            OP_LUI, OP_AUIPC, OP_OP_IMM, OP_OP: begin
              if (rd_idx != 5'd0) begin
                regfile[rd_idx] <= alu_result;
              end
              pc    <= pc + 32'd4;
              state <= ST_FETCH;
            end

            OP_JAL: begin
              if (rd_idx != 5'd0) begin
                regfile[rd_idx] <= pc + 32'd4;
              end
              pc    <= pc + imm_j;
              state <= ST_FETCH;
            end

            OP_JALR: begin
              if (rd_idx != 5'd0) begin
                regfile[rd_idx] <= pc + 32'd4;
              end
              pc    <= (rs1_data + imm_i) & ~32'd1;
              state <= ST_FETCH;
            end

            OP_BRANCH: begin
              if (branch_taken) begin
                pc <= pc + imm_b;
              end else begin
                pc <= pc + 32'd4;
              end
              state <= ST_FETCH;
            end

            OP_LOAD: begin
              mem_addr <= rs1_data + imm_i;
              mem_req  <= 1'b1;
              mem_we   <= 1'b0;
              mem_be   <= 4'b1111;
              state    <= ST_LOAD_WAIT;
            end

            OP_STORE: begin
              mem_addr  <= rs1_data + imm_s;
              mem_req   <= 1'b1;
              mem_we    <= 1'b1;
              mem_be    <= (funct3 == 3'b000) ? 4'b0001 :
                           (funct3 == 3'b001) ? 4'b0011 : 4'b1111;
              mem_wdata <= rs2_data;
              state     <= ST_STORE_WAIT;
            end

            default: begin
              pc    <= pc + 32'd4;
              state <= ST_FETCH;
            end
          endcase
        end

        ST_STORE_WAIT: begin
          mem_req <= 1'b0;
          mem_we  <= 1'b0;
          pc      <= pc + 32'd4;
          state   <= ST_FETCH;
        end

        ST_LOAD_WAIT: begin
          mem_req <= 1'b0;
          state   <= ST_LOAD_CAPTURE;
        end

        ST_LOAD_CAPTURE: begin
          if (rd_idx != 5'd0) begin
            case (funct3)
              3'b000:  regfile[rd_idx] <= {{24{mem_rdata[7]}}, mem_rdata[7:0]}; // LB
              3'b001:  regfile[rd_idx] <= {{16{mem_rdata[15]}}, mem_rdata[15:0]}; // LH
              3'b010:  regfile[rd_idx] <= mem_rdata; // LW
              3'b100:  regfile[rd_idx] <= {24'd0, mem_rdata[7:0]}; // LBU
              3'b101:  regfile[rd_idx] <= {16'd0, mem_rdata[15:0]}; // LHU
              default: regfile[rd_idx] <= mem_rdata;
            endcase
          end
          pc    <= pc + 32'd4;
          state <= ST_FETCH;
        end

        default: state <= ST_FETCH;
      endcase
    end
  end

endmodule
