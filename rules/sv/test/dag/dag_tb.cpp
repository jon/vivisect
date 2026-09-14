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

#include <iostream>
#include <cassert>
#include "Vdag_encoder.h"
#include "verilated.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vdag_encoder* dut = new Vdag_encoder;

    dut->clk = 0;
    dut->rst_n = 0;
    dut->valid_in = 0;
    dut->eval();

    // Reset cycle
    for (int i = 0; i < 4; ++i) {
        dut->clk = !dut->clk;
        dut->eval();
    }
    dut->rst_n = 1;
    dut->eval();

    // Test transaction: drive input
    dut->clk = 0; dut->eval();
    dut->valid_in = 1;
    // packet_in has packed struct representation
    dut->clk = 1; dut->eval();
    dut->clk = 0; dut->eval();
    dut->valid_in = 0;
    dut->clk = 1; dut->eval();

    delete dut;
    std::cout << "[dag_tb.cpp] SUCCESS: C++ driver executed cleanly." << std::endl;
    return 0;
}
