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

module ordering_dut (
  input  logic clk,
  input  logic rst_n,
  ordering_if.consumer bus
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bus.ack <= 1'b0;
    end else begin
      bus.ack <= bus.msg.valid;
    end
  end
endmodule
