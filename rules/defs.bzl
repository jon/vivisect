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

# AMD / Xilinx Simulation Rules
xelab = _xelab
xsim_test = _xsim_test
xvlog = _xvlog
