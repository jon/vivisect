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

"""Hardware Starlark Providers for AMD FPGA Tools and Verilator.

Defines the metadata containers used across vivisect rules to propagate
SystemVerilog source sets, Tcl scripts/constraints, simulation snapshots,
design checkpoints, parts, boards, and Verilator C++ transpile artifacts.
"""

SvInfo = provider(
    doc = "Propagates SystemVerilog/Verilog sources, headers, includes, defines, waivers, and data files.",
    fields = {
        "srcs": "depset of File: Direct SystemVerilog/Verilog source files.",
        "hdrs": "depset of File: Header files (.svh, .vh).",
        "includes": "depset of string: Include directories passed to preprocessor.",
        "defines": "depset of string: Preprocessor macro definitions (e.g. NAME or NAME=VAL).",
        "pkgs": "depset of File: SV package files requiring compilation prior to modules.",
        "interfaces": "depset of File: SV interface files requiring compilation prior to modules.",
        "modules": "depset of File: SV module files compiled after packages and interfaces.",
        "data": "depset of File: Supporting data and memory initialization files (.mem, .hex, .dat).",
        "waivers": "depset of File: Verilator .vlt configuration/waiver files.",
        "transitive_srcs": "depset of File: All upstream transitive source files in topological order.",
    },
)

TclInfo = provider(
    doc = "Propagates Tcl automation scripts, design constraints, and data files.",
    fields = {
        "scripts": "depset of File: Tcl helper or automation scripts.",
        "constraints": "depset of File: XDC constraint files for synthesis and implementation.",
        "data": "depset of File: Supporting memory initialization files (.mem, .coe).",
    },
)

VivadoConstraintsInfo = provider(
    doc = "Propagates physical and timing constraints partitioned by synthesis/implementation stage and cell scoping.",
    fields = {
        "synth_constraints": "depset of File: Constraints applied during synthesis.",
        "impl_constraints": "depset of File: Constraints applied during implementation.",
        "scoped_constraints": "depset of struct: Scoped constraints with cell or ref targeting.",
    },
)

VivadoPartInfo = provider(
    doc = "Propagates canonical AMD/Xilinx FPGA part specification.",
    fields = {
        "part": "string: Canonical full part string (<device><package><speed_grade>).",
        "family": "string: FPGA architecture family (e.g. 'artix7', 'kintexuplus').",
        "device": "string: Silicon device name (e.g. 'xc7a100t').",
        "package": "string: Silicon package identifier (e.g. 'csg324').",
        "speed": "string: Silicon speed grade (e.g. '-1').",
    },
)

VivadoBoardInfo = provider(
    doc = "Propagates FPGA development board definitions, binding a part to base pinout constraints.",
    fields = {
        "part_info": "VivadoPartInfo: Target FPGA part provider.",
        "part": "string: Target FPGA canonical part string.",
        "board_part": "string: Optional AMD board_part identifier (e.g. 'digilentinc.com:arty-a7-100:part0:1.1').",
        "constraints": "VivadoConstraintsInfo: Base board constraints (pinouts, clocks, peripherals).",
    },
)

XsimSnapshotInfo = provider(
    doc = "Propagates an elaborated xsim simulation snapshot directory.",
    fields = {
        "snapshot_dir": "File (directory): The directory artifact containing xsim.dir.",
        "top": "string: The top-level testbench or module name.",
        "snapshot_name": "string: The snapshot name inside xsim.dir/.",
    },
)

VivadoDcpInfo = provider(
    doc = "Propagates a Vivado Design Checkpoint (.dcp) and associated design reports.",
    fields = {
        "dcp": "File: The checkpoint (.dcp) file output from synthesis or implementation.",
        "top": "string: Top-level module name.",
        "stage": "string: Design stage, either 'synth' or 'impl'.",
        "reports": "dict of string to File: Map of report types (e.g. 'timing', 'utilization', 'utilization_json') to report files.",
        "stub": "File: Optional generated black-box Verilog stub (.v) for out-of-context checkpoints.",
        "part": "string: Target FPGA part string.",
        "out_of_context": "bool: Whether the checkpoint was synthesized out-of-context.",
        "cells": "dict of string to File: Map of hierarchical cell instance paths to child cell checkpoints.",
    },
)

VerilatorCppInfo = provider(
    doc = "Propagates C++ headers and sources generated by Verilator transpilation.",
    fields = {
        "hdrs": "depset of File: Generated C++ header files (.h).",
        "srcs": "depset of File: Generated C++ source files (.cpp).",
        "top": "string: Top-level module name.",
    },
)

VivadoBitstreamInfo = provider(
    doc = "Propagates FPGA bitstream artifacts (.bit, optional .bin, and optional debug probes .ltx).",
    fields = {
        "bit": "File: Primary FPGA configuration bitstream (.bit) file.",
        "bin": "File: Optional raw binary file (.bin) for SPI flash memory programming, or None.",
        "probes": "File: Optional ILA/VIO debug probes file (.ltx), or None.",
        "top": "string: Top-level module name.",
        "part": "string: Target FPGA canonical part string.",
        "checkpoint": "File: The implementation checkpoint (.dcp) used to generate the bitstream.",
    },
)
