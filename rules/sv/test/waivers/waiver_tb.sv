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
`default_nettype none

module waiver_tb;

    logic [3:0] in_val;
    wire  [7:0] out_val;

    waiver_mod dut (
        .in_val(in_val),
        .out_val(out_val)
    );

    initial begin
        in_val = 4'hA;
        #10;
        if (out_val !== 8'h0A) begin
            $display("ERROR: Expected out_val=0x0A, got 0x%02h", out_val);
            $finish(1);
        end
        $display("PASS: waiver_tb completed successfully");
        $finish(0);
    end

endmodule
