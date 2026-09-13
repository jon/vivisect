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
#include "Vcounter.h"
#include "verilated.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vcounter* dut = new Vcounter;

    // Initialize inputs
    dut->clk = 0;
    dut->rst_n = 0;
    dut->en = 0;
    dut->eval();

    // Release reset
    dut->rst_n = 1;
    dut->eval();
    assert(dut->count == 0);

    // Step clock with enable low (should not count)
    for (int i = 0; i < 5; ++i) {
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
    }
    assert(dut->count == 0);

    // Enable counter and tick 16 cycles
    dut->en = 1;
    for (int i = 0; i < 16; ++i) {
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
    }
    std::cout << "Counter value after 16 enabled cycles: " << (int)dut->count << std::endl;
    assert(dut->count == 16);

    // Assert reset asynchronously
    dut->rst_n = 0;
    dut->eval();
    assert(dut->count == 0);

    delete dut;
    std::cout << "All Verilator counter assertions passed successfully!" << std::endl;
    return 0;
}
