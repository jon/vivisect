# Copyright 2026 The Vivisect Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Verilator test macro integrating with rules_cc and verilator_library."""

load("@rules_cc//cc:defs.bzl", "cc_test")
load(":verilator_library.bzl", "verilator_library")

def verilator_test(
        name,
        top,
        tb = None,
        srcs = [],
        hdrs = [],
        deps = [],
        waivers = [],
        data = [],
        verilator_flags = ["-Wall", "-Wno-fatal"],
        copts = [],
        defines = [],
        includes = [],
        **kwargs):
    """Compiles SystemVerilog with Verilator and builds a native test using rules_cc.

    Supports two test execution modes:
      1. Pure SystemVerilog Testbench (`tb = None`):
         Verilates `top` (the testbench module) with `--timing` and `--main`, running
         the SystemVerilog event scheduler and simulation loop directly until `$finish`.
      2. C++ Testbench (`tb = "my_tb.cpp"`):
         Verilates `top` (the synthesizable DUT) into a C++ model class and compiles
         `tb` as the test executable driver.

    Args:
        name: Name of the test target.
        top: Name of the top-level SystemVerilog module (DUT if `tb` provided, TB if omitted).
        tb: Optional C++ testbench source file (.cpp). If None, runs in pure SV testbench mode.
        srcs: Optional direct SystemVerilog source files.
        hdrs: Optional direct header files.
        deps: sv_library dependencies providing SystemVerilog sources.
        waivers: Verilator .vlt configuration and waiver files.
        verilator_flags: Flags passed to the Verilator transpiler.
        copts: C++ compiler options.
        defines: Preprocessor defines for C++ compilation.
        includes: Include directories for C++ compilation.
        **kwargs: Common test attributes passed to cc_test.
    """
    model_target = name + "_model"

    effective_vflags = list(verilator_flags)
    if "--assert" not in effective_vflags:
        effective_vflags.append("--assert")

    if tb == None:
        # Pure SystemVerilog testbench mode: generate main() and enable timing
        if "--timing" not in effective_vflags:
            effective_vflags.append("--timing")
        if "--main" not in effective_vflags:
            effective_vflags.append("--main")

        verilator_library(
            name = model_target,
            top = top,
            srcs = srcs,
            hdrs = hdrs,
            deps = deps,
            waivers = waivers,
            verilator_flags = effective_vflags,
            copts = copts,
            defines = defines,
            includes = includes,
            alwayslink = True,
            visibility = ["//visibility:private"],
        )

        cc_test(
            name = name,
            srcs = [],
            data = data,
            deps = [
                ":" + model_target,
                "@verilator_default//:runtime",
            ],
            copts = ["-std=c++20"] + copts,
            defines = defines,
            includes = includes,
            **kwargs
        )
    else:
        # C++ testbench mode: user provides custom main() in tb (.cpp)
        verilator_library(
            name = model_target,
            top = top,
            srcs = srcs,
            hdrs = hdrs,
            deps = deps,
            waivers = waivers,
            verilator_flags = effective_vflags,
            copts = copts,
            defines = defines,
            includes = includes,
            visibility = ["//visibility:private"],
        )

        cc_test(
            name = name,
            srcs = [tb],
            data = data,
            deps = [
                ":" + model_target,
                "@verilator_default//:runtime",
            ],
            copts = ["-std=c++20"] + copts,
            defines = defines,
            includes = includes,
            **kwargs
        )
