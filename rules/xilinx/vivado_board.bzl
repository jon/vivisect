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

"""Rule defining an FPGA development board, binding silicon part with pin constraints."""

load(
    "//rules:providers.bzl",
    "VivadoBoardInfo",
    "VivadoConstraintsInfo",
    "VivadoPartInfo",
)

def _vivado_board_impl(ctx):
    part_info = ctx.attr.part[VivadoPartInfo]

    synth_depsets = []
    impl_depsets = []
    scoped_depsets = []

    # Direct XDC files default to synth and impl
    direct_xdc = ctx.files.xdc
    if direct_xdc:
        synth_depsets.append(depset(direct_xdc))
        impl_depsets.append(depset(direct_xdc))

    # Constraints libraries
    for dep in ctx.attr.constraints:
        if VivadoConstraintsInfo in dep:
            c_info = dep[VivadoConstraintsInfo]
            synth_depsets.append(c_info.synth_constraints)
            impl_depsets.append(c_info.impl_constraints)
            scoped_depsets.append(c_info.scoped_constraints)

    board_constraints = VivadoConstraintsInfo(
        synth_constraints = depset(transitive = synth_depsets),
        impl_constraints = depset(transitive = impl_depsets),
        scoped_constraints = depset(transitive = scoped_depsets),
    )

    board_info = VivadoBoardInfo(
        part_info = part_info,
        part = part_info.part,
        board_part = ctx.attr.board_part,
        constraints = board_constraints,
    )

    all_files = depset(direct_xdc, transitive = [dep[DefaultInfo].files for dep in ctx.attr.constraints])

    return [
        DefaultInfo(files = all_files),
        board_info,
        part_info,
        board_constraints,
    ]

vivado_board = rule(
    implementation = _vivado_board_impl,
    doc = "Defines an FPGA target board unifying silicon part, board part, and base constraints.",
    attrs = {
        "part": attr.label(
            mandatory = True,
            providers = [VivadoPartInfo],
            doc = "Target FPGA silicon part (vivado_part target).",
        ),
        "board_part": attr.string(
            default = "",
            doc = "AMD Vivado board part string (e.g. 'digilentinc.com:arty-a7-100:part0:1.1').",
        ),
        "constraints": attr.label_list(
            providers = [VivadoConstraintsInfo],
            default = [],
            doc = "xdc_library targets providing base pinouts, clock oscillators, and peripherals.",
        ),
        "xdc": attr.label_list(
            allow_files = [".xdc"],
            default = [],
            doc = "Direct XDC constraint files for the board.",
        ),
    },
)
