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

module glbl_tb;

    wire out;
    LUT2 #(.INIT(4'h8)) u_lut (
        .I0(1'b1),
        .I1(1'b1),
        .O(out)
    );

    initial begin
        #1;
        // Verify glbl GSR is initially asserted
        if (glbl.GSR !== 1'b1) begin
            $fatal(1, "Expected glbl.GSR to be 1 initially, got %b", glbl.GSR);
        end

        // Wait for GSR to deassert (ROC_WIDTH = 100ns)
        #150;
        if (glbl.GSR !== 1'b0) begin
            $fatal(1, "Expected glbl.GSR to deassert after 100ns, got %b", glbl.GSR);
        end

        // Verify UNISIM primitive functionality
        if (out !== 1'b1) begin
            $fatal(1, "Expected LUT2 output 1, got %b", out);
        end

        $display("PASS: glbl_tb executed successfully with unisims_ver and glbl.");
        $finish(0);
    end

endmodule
