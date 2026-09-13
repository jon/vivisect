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

"""SystemVerilog library rule propagating sources, packages, headers, includes, and defines."""

load("//rules:providers.bzl", "SvInfo")

def _sv_library_impl(ctx):
    raw_srcs = ctx.files.srcs
    direct_srcs = [s for s in raw_srcs if not s.path.endswith(".vlt")]
    direct_src_waivers = [s for s in raw_srcs if s.path.endswith(".vlt")]
    direct_waivers = direct_src_waivers + ctx.files.waivers

    direct_hdrs = ctx.files.hdrs
    direct_pkgs = ctx.files.pkgs
    direct_interfaces = ctx.files.interfaces
    direct_data = ctx.files.data
    direct_defines = list(ctx.attr.defines)

    # Derive include paths from hdrs if enabled
    derived_includes = []
    if ctx.attr.include_hdrs_dirs:
        hdr_dirs = {}
        for h in direct_hdrs:
            d = h.dirname
            if d not in hdr_dirs:
                hdr_dirs[d] = True
                derived_includes.append(d)

    all_direct_includes = list(ctx.attr.includes) + derived_includes

    # Collect transitive dependencies
    dep_hdrs = []
    dep_includes = []
    dep_defines = []
    dep_pkgs = []
    dep_interfaces = []
    dep_modules = []
    dep_data = []
    dep_waivers = []

    for dep in ctx.attr.deps:
        if SvInfo in dep:
            info = dep[SvInfo]
            if hasattr(info, "pkgs") and info.pkgs:
                dep_pkgs.append(info.pkgs)
            if hasattr(info, "interfaces") and info.interfaces:
                dep_interfaces.append(info.interfaces)
            if hasattr(info, "modules") and info.modules:
                dep_modules.append(info.modules)
            elif hasattr(info, "transitive_srcs") and info.transitive_srcs:
                known_pkgs = {f.path: True for f in info.pkgs.to_list()} if hasattr(info, "pkgs") and info.pkgs else {}
                known_ifs = {f.path: True for f in info.interfaces.to_list()} if hasattr(info, "interfaces") and info.interfaces else {}
                fallback = [f for f in info.transitive_srcs.to_list() if f.path not in known_pkgs and f.path not in known_ifs]
                if fallback:
                    dep_modules.append(depset(fallback))
            dep_hdrs.append(info.hdrs)
            dep_includes.append(info.includes)
            dep_defines.append(info.defines)
            if hasattr(info, "data") and info.data:
                dep_data.append(info.data)
            if hasattr(info, "waivers") and info.waivers:
                dep_waivers.append(info.waivers)

    transitive_pkgs = depset(direct_pkgs, order = "postorder", transitive = dep_pkgs)
    transitive_interfaces = depset(direct_interfaces, order = "postorder", transitive = dep_interfaces)
    transitive_modules = depset(direct_srcs, order = "postorder", transitive = dep_modules)

    # Postorder traversal ensures upstream packages precede interfaces, which precede modules
    transitive_srcs = depset(
        order = "postorder",
        transitive = [transitive_pkgs, transitive_interfaces, transitive_modules],
    )

    waivers_depset = depset(direct_waivers, transitive = dep_waivers)

    sv_info = SvInfo(
        srcs = depset(direct_srcs),
        hdrs = depset(direct_hdrs, transitive = dep_hdrs),
        includes = depset(all_direct_includes, transitive = dep_includes),
        defines = depset(direct_defines, transitive = dep_defines),
        pkgs = transitive_pkgs,
        interfaces = transitive_interfaces,
        modules = transitive_modules,
        data = depset(direct_data, transitive = dep_data),
        waivers = waivers_depset,
        transitive_srcs = transitive_srcs,
    )

    all_direct_files = direct_srcs + direct_hdrs + direct_pkgs + direct_interfaces + direct_data + direct_waivers
    return [
        DefaultInfo(files = depset(all_direct_files)),
        sv_info,
    ]

sv_library = rule(
    implementation = _sv_library_impl,
    doc = "Defines a SystemVerilog library with transitive dependencies, includes, and defines.",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".sv", ".v", ".vlt"],
            doc = "SystemVerilog and Verilog source files (.sv, .v, .vlt).",
        ),
        "hdrs": attr.label_list(
            allow_files = [".svh", ".vh", ".h"],
            doc = "SystemVerilog and Verilog header files (.svh, .vh, .h).",
        ),
        "pkgs": attr.label_list(
            allow_files = [".sv", ".v"],
            default = [],
            doc = "SystemVerilog package files compiled before interfaces and modules.",
        ),
        "interfaces": attr.label_list(
            allow_files = [".sv", ".v"],
            default = [],
            doc = "SystemVerilog interface files compiled after packages and before modules.",
        ),
        "waivers": attr.label_list(
            allow_files = [".vlt"],
            default = [],
            doc = "Verilator .vlt configuration and waiver files.",
        ),
        "include_hdrs_dirs": attr.bool(
            default = False,
            doc = "If True, automatically adds parent directories of declared hdrs to include search paths.",
        ),
        "includes": attr.string_list(
            default = [],
            doc = "Include directories passed to preprocessors (-I or +incdir+).",
        ),
        "defines": attr.string_list(
            default = [],
            doc = "Macro definitions passed to preprocessor (NAME or NAME=VAL).",
        ),
        "data": attr.label_list(
            allow_files = True,
            default = [],
            doc = "Supporting data and memory initialization files (.mem, .hex, .dat).",
        ),
        "deps": attr.label_list(
            providers = [SvInfo],
            default = [],
            doc = "Dependencies providing SvInfo.",
        ),
    },
)
