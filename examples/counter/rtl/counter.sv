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

// A parameterizable SystemVerilog synchronous counter.
module counter #(
    parameter int WIDTH = 8
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 en,
    output reg  [WIDTH-1:0]     count
);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= '0;
    end else if (en) begin
      count <= count + 1'b1;
    end
  end

endmodule
