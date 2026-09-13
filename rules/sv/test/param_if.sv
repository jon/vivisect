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

interface param_if #(
  parameter int WIDTH,
  parameter int DEPTH
)(
  input logic clk
);
  logic [WIDTH-1:0] data;
  logic             valid;

  modport producer (
    input  clk,
    output data, valid
  );

  modport consumer (
    input clk, data, valid
  );
endinterface
