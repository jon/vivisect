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

"""Rule for managing AMD Vivado physical and timing design constraints (XDC)."""

load("//rules:providers.bzl", "VivadoConstraintsInfo")

def _xdc_library_impl(ctx):
    synth_direct = []
    impl_direct = []

    used_in = ctx.attr.used_in
    for f in ctx.files.srcs:
        if "synth" in used_in:
            synth_direct.append(f)
        if "impl" in used_in:
            impl_direct.append(f)

    synth_depsets = [depset(synth_direct)]
    impl_depsets = [depset(impl_direct)]
    scoped_list = []

    if ctx.attr.scoped_to_ref or ctx.attr.scoped_to_cells:
        for f in ctx.files.srcs:
            scoped_list.append(struct(
                file = f,
                scoped_to_ref = ctx.attr.scoped_to_ref,
                scoped_to_cells = ctx.attr.scoped_to_cells,
                used_in = used_in,
            ))

    scoped_depsets = [depset(scoped_list)]

    for dep in ctx.attr.deps:
        if VivadoConstraintsInfo in dep:
            c_info = dep[VivadoConstraintsInfo]
            synth_depsets.append(c_info.synth_constraints)
            impl_depsets.append(c_info.impl_constraints)
            scoped_depsets.append(c_info.scoped_constraints)

    all_files = depset(ctx.files.srcs, transitive = [dep[DefaultInfo].files for dep in ctx.attr.deps])

    return [
        DefaultInfo(files = all_files),
        VivadoConstraintsInfo(
            synth_constraints = depset(transitive = synth_depsets),
            impl_constraints = depset(transitive = impl_depsets),
            scoped_constraints = depset(transitive = scoped_depsets),
        ),
    ]

xdc_library = rule(
    implementation = _xdc_library_impl,
    doc = "Collects and categorizes Vivado Design Constraints (.xdc) by stage and scoping.",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".xdc"],
            doc = "XDC constraint files.",
        ),
        "deps": attr.label_list(
            providers = [VivadoConstraintsInfo],
            default = [],
            doc = "Upstream xdc_library targets.",
        ),
        "used_in": attr.string_list(
            default = ["synth", "impl"],
            doc = "Stages where these constraints apply: 'synth', 'impl', or both.",
        ),
        "scoped_to_ref": attr.string(
            default = "",
            doc = "Optional module reference name to scope constraints to (sets SCOPED_TO_REF).",
        ),
        "scoped_to_cells": attr.string_list(
            default = [],
            doc = "Optional cell instance paths to scope constraints to (sets SCOPED_TO_CELLS).",
        ),
    },
)
