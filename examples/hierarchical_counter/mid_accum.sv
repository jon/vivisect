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

// Mid-level accumulator instantiating leaf_adder as u_leaf
module mid_accum (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] incr,
    output logic [7:0] count
);
    logic [7:0] next_count;

    leaf_adder u_leaf (
        .a(count),
        .b(incr),
        .sum(next_count)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0;
        end else begin
            count <= next_count;
        end
    end
endmodule
