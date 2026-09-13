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

"""Public API entrypoint for vivisect Bazel rules."""

load(
    ":providers.bzl",
    _SvInfo = "SvInfo",
    _TclInfo = "TclInfo",
    _VerilatorCppInfo = "VerilatorCppInfo",
    _VivadoBoardInfo = "VivadoBoardInfo",
    _VivadoConstraintsInfo = "VivadoConstraintsInfo",
    _VivadoDcpInfo = "VivadoDcpInfo",
    _VivadoPartInfo = "VivadoPartInfo",
    _XsimSnapshotInfo = "XsimSnapshotInfo",
)
load(
    "//rules/sv:sv_interface.bzl",
    _sv_interface = "sv_interface",
)
load(
    "//rules/sv:sv_library.bzl",
    _sv_library = "sv_library",
)
load(
    "//rules/sv:sv_package.bzl",
    _sv_package = "sv_package",
)
load(
    "//rules/sv:verilator_lint.bzl",
    _verilator_lint_test = "verilator_lint_test",
)
load(
    "//rules/sv:verilator_library.bzl",
    _verilator_library = "verilator_library",
)
load(
    "//rules/sv:verilator_test.bzl",
    _verilator_test = "verilator_test",
)
load(
    "//rules/xilinx:xelab.bzl",
    _xelab = "xelab",
)
load(
    "//rules/xilinx:xsim_test.bzl",
    _xsim_test = "xsim_test",
)
load(
    "//rules/xilinx:xvlog.bzl",
    _xvlog = "xvlog",
)

# Hardware Starlark Providers
SvInfo = _SvInfo
TclInfo = _TclInfo
VerilatorCppInfo = _VerilatorCppInfo
VivadoBoardInfo = _VivadoBoardInfo
VivadoConstraintsInfo = _VivadoConstraintsInfo
VivadoDcpInfo = _VivadoDcpInfo
VivadoPartInfo = _VivadoPartInfo
XsimSnapshotInfo = _XsimSnapshotInfo

# SystemVerilog & Verilator Rules
sv_interface = _sv_interface
sv_library = _sv_library
sv_package = _sv_package
verilator_library = _verilator_library
verilator_lint_test = _verilator_lint_test
verilator_test = _verilator_test

# AMD / Xilinx Simulation Rules
xelab = _xelab
xsim_test = _xsim_test
xvlog = _xvlog
