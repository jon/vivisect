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

module cdc_fifo_tb;

  localparam int DATA_WIDTH = 32;
  localparam int ADDR_WIDTH = 4; // 16 words depth for fast TB coverage
  localparam int NUM_TRANSFERS = 300;

  // Clocks and resets
  logic wclk = 0;
  logic wrst_n = 0;
  logic rclk = 0;
  logic rrst_n = 0;

  // Clock generation: wclk = 10ns (100MHz), rclk = 14ns (~71.4MHz) - asynchronous ratio
  always #5 wclk = ~wclk;
  always #7 rclk = ~rclk;

  // FIFO interface
  logic                  winc = 0;
  logic [DATA_WIDTH-1:0] wdata = '0;
  wire                   wfull;
  wire                   walmost_full;

  logic                  rinc = 0;
  wire  [DATA_WIDTH-1:0] rdata;
  wire                   rempty;
  wire                   ralmost_empty;

  // DUT instantiation
  async_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .ALMOST_FULL_THRESH(2),
    .ALMOST_EMPTY_THRESH(2)
  ) dut (
    .wclk(wclk),
    .wrst_n(wrst_n),
    .winc(winc),
    .wdata(wdata),
    .wfull(wfull),
    .walmost_full(walmost_full),
    .rclk(rclk),
    .rrst_n(rrst_n),
    .rinc(rinc),
    .rdata(rdata),
    .rempty(rempty),
    .ralmost_empty(ralmost_empty)
  );

  // Scoreboard queue
  logic [DATA_WIDTH-1:0] write_queue[$];
  int write_count = 0;
  int read_count = 0;
  bit test_done = 0;

  // Reset sequence
  initial begin
    #20;
    @(negedge wclk) wrst_n = 1;
    @(negedge rclk) rrst_n = 1;
  end

  // Writer process
  initial begin
    @(posedge wrst_n);
    while (write_count < NUM_TRANSFERS) begin
      @(negedge wclk);
      if (!wfull && ($urandom_range(0, 10) > 2)) begin
        winc  <= 1'b1;
        wdata <= 32'hA000_0000 | write_count;
        write_queue.push_back(32'hA000_0000 | write_count);
        write_count++;
      end else begin
        winc <= 1'b0;
      end
    end
    @(negedge wclk);
    winc <= 1'b0;
  end

  // Reader process
  initial begin
    @(posedge rrst_n);
    while (read_count < NUM_TRANSFERS) begin
      @(negedge rclk);
      if (!rempty && ($urandom_range(0, 10) > 2)) begin
        rinc <= 1'b1;
        @(posedge rclk);
        #1; // Delay after clock edge for synchronous read
        if (write_queue.size() > 0) begin
          logic [DATA_WIDTH-1:0] expected = write_queue.pop_front();
          if (rdata !== expected) begin
            $fatal(1, "Data mismatch! Got 0x%08h, expected 0x%08h at transfer %0d", rdata, expected, read_count);
          end
          read_count++;
        end else begin
          $fatal(1, "Read occurred but write_queue is empty!");
        end
      end else begin
        rinc <= 1'b0;
      end
    end
    @(negedge rclk);
    rinc <= 1'b0;
    test_done = 1;
  end

  // Watchdog timeout and pass check
  initial begin
    #200000;
    if (!test_done) begin
      $fatal(1, "Test timeout! write_count=%0d, read_count=%0d", write_count, read_count);
    end
  end

  initial begin
    wait(test_done);
    #100;
    $display("SUCCESS: CDC FIFO verified %0d transfers across asynchronous clock domains without drop or corruption.", read_count);
    $finish;
  end

endmodule
