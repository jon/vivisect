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

"""Unit tests for vivisect Starlark providers."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//rules:providers.bzl",
    "SvInfo",
    "TclInfo",
    "VerilatorCppInfo",
    "VivadoBitstreamInfo",
    "VivadoBoardInfo",
    "VivadoConstraintsInfo",
    "VivadoDcpInfo",
    "VivadoPartInfo",
    "XsimSnapshotInfo",
)

def _providers_test_impl(ctx):
    env = unittest.begin(ctx)

    # Test SvInfo
    sv = SvInfo(
        srcs = depset([]),
        hdrs = depset([]),
        includes = depset(["src/include"]),
        defines = depset(["SYNTHESIS=1"]),
        pkgs = depset([]),
        interfaces = depset([]),
        modules = depset([]),
        data = depset([]),
        waivers = depset([]),
        transitive_srcs = depset([]),
    )
    asserts.equals(env, ["src/include"], sv.includes.to_list())
    asserts.equals(env, ["SYNTHESIS=1"], sv.defines.to_list())
    asserts.equals(env, [], sv.pkgs.to_list())
    asserts.equals(env, [], sv.interfaces.to_list())
    asserts.equals(env, [], sv.modules.to_list())
    asserts.equals(env, [], sv.data.to_list())
    asserts.equals(env, [], sv.waivers.to_list())

    # Test TclInfo
    tcl = TclInfo(
        scripts = depset([]),
        constraints = depset([]),
        data = depset([]),
    )
    asserts.equals(env, [], tcl.constraints.to_list())

    # Test VivadoConstraintsInfo
    c_info = VivadoConstraintsInfo(
        synth_constraints = depset([]),
        impl_constraints = depset([]),
        scoped_constraints = depset([]),
    )
    asserts.equals(env, [], c_info.synth_constraints.to_list())

    # Test VivadoPartInfo
    part = VivadoPartInfo(
        part = "xc7a100tcsg324-1",
        family = "artix7",
        device = "xc7a100t",
        package = "csg324",
        speed = "-1",
    )
    asserts.equals(env, "xc7a100tcsg324-1", part.part)
    asserts.equals(env, "artix7", part.family)
    asserts.equals(env, "csg324", part.package)

    # Test VivadoBoardInfo
    board = VivadoBoardInfo(
        part_info = part,
        part = part.part,
        board_part = "digilentinc.com:arty-a7-100:part0:1.1",
        constraints = c_info,
    )
    asserts.equals(env, "xc7a100tcsg324-1", board.part)
    asserts.equals(env, "digilentinc.com:arty-a7-100:part0:1.1", board.board_part)

    # Test XsimSnapshotInfo
    snap = XsimSnapshotInfo(
        snapshot_dir = None,
        top = "tb_top",
        snapshot_name = "tb_top_snap",
    )
    asserts.equals(env, "tb_top", snap.top)
    asserts.equals(env, "tb_top_snap", snap.snapshot_name)

    # Test VivadoDcpInfo
    dcp = VivadoDcpInfo(
        dcp = None,
        top = "top_module",
        stage = "synth",
        reports = {"timing": None},
        stub = None,
        part = "xc7a100tcsg324-1",
        out_of_context = True,
        cells = {},
    )
    asserts.equals(env, "top_module", dcp.top)
    asserts.equals(env, "synth", dcp.stage)
    asserts.true(env, "timing" in dcp.reports)
    asserts.true(env, dcp.out_of_context)
    asserts.equals(env, "xc7a100tcsg324-1", dcp.part)

    # Test VerilatorCppInfo
    vcpp = VerilatorCppInfo(
        hdrs = depset([]),
        srcs = depset([]),
        top = "counter",
    )
    asserts.equals(env, "counter", vcpp.top)

    # Test VivadoBitstreamInfo
    bitstream = VivadoBitstreamInfo(
        bit = None,
        bin = None,
        probes = None,
        top = "soc_top",
        part = "xc7a100tcsg324-1",
        checkpoint = None,
    )
    asserts.equals(env, "soc_top", bitstream.top)
    asserts.equals(env, "xc7a100tcsg324-1", bitstream.part)
    asserts.equals(env, None, bitstream.bit)
    asserts.equals(env, None, bitstream.bin)
    asserts.equals(env, None, bitstream.probes)

    return unittest.end(env)

providers_test = unittest.make(_providers_test_impl)

def providers_test_suite(name):
    unittest.suite(
        name,
        providers_test,
    )
