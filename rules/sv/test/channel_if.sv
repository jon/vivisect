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

interface channel_if #(
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 16
)(
  input logic clk,
  input logic rst_n
);
  logic [ADDR_WIDTH-1:0] addr;
  logic [DATA_WIDTH-1:0] wdata;
  logic [DATA_WIDTH-1:0] rdata;
  logic                  valid;
  logic                  ready;

  modport manager (
    input  clk, rst_n, rdata, ready,
    output addr, wdata, valid
  );

  modport subordinate (
    input  clk, rst_n, addr, wdata, valid,
    output rdata, ready
  );

  modport monitor (
    input clk, rst_n, addr, wdata, rdata, valid, ready
  );
endinterface
