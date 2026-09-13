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

"""Verilator C++ library rule and transpilation integrating with rules_cc."""

load("@rules_cc//cc:defs.bzl", "cc_library")
load("//rules:providers.bzl", "SvInfo", "VerilatorCppInfo")
load("//rules:stage.bzl", "verilator_transition")

VERILATOR_TOOLCHAIN_TYPE = Label("//rules/toolchains:verilator_toolchain_type")

def _verilator_transpile_impl(ctx):
    tc = ctx.toolchains[VERILATOR_TOOLCHAIN_TYPE].verilator

    dep_pkgs = []
    dep_interfaces = []
    dep_modules = []
    all_hdrs = []
    all_includes = []
    all_defines = []
    all_waivers = []

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
            all_hdrs.extend(info.hdrs.to_list())
            all_includes.extend(info.includes.to_list())
            all_defines.extend(info.defines.to_list())
            if hasattr(info, "waivers") and info.waivers:
                all_waivers.extend(info.waivers.to_list())

    # Add direct sources if given
    raw_srcs = ctx.files.srcs
    direct_srcs = [s for s in raw_srcs if not s.path.endswith(".vlt")]
    direct_src_waivers = [s for s in raw_srcs if s.path.endswith(".vlt")]

    all_waivers.extend(direct_src_waivers)
    all_waivers.extend(ctx.files.waivers)

    # Order sources strictly: packages -> interfaces -> modules -> direct sources
    ordered_pkgs = depset(order = "postorder", transitive = dep_pkgs).to_list()
    ordered_interfaces = depset(order = "postorder", transitive = dep_interfaces).to_list()
    ordered_modules = depset(order = "postorder", transitive = dep_modules).to_list()

    all_srcs = ordered_pkgs + ordered_interfaces + ordered_modules + direct_srcs
    all_hdrs.extend(ctx.files.hdrs)

    # De-duplicate sources preserving order
    seen_srcs = {}
    dedup_srcs = []
    for s in all_srcs:
        if s.path not in seen_srcs:
            seen_srcs[s.path] = True
            dedup_srcs.append(s)

    # De-duplicate waivers preserving order
    seen_waivers = {}
    dedup_waivers = []
    for w in all_waivers:
        if w.path not in seen_waivers:
            seen_waivers[w.path] = True
            dedup_waivers.append(w)

    out_dir = ctx.actions.declare_directory(ctx.label.name + "_dir")

    args = [
        tc.verilator_path,
        "--cc",
        "--top-module",
        ctx.attr.top,
        "--Mdir",
        out_dir.path,
        "--prefix",
        "V" + ctx.attr.top,
    ]

    for inc in all_includes:
        args.append("-I" + inc)

    for d in all_defines:
        args.append("-D" + d)

    args.extend(ctx.attr.verilator_flags)

    for w in dedup_waivers:
        args.append(w.path)

    for s in dedup_srcs:
        args.append(s.path)

    # Verilator generates .mk, .dat, and .d files in Mdir.
    # Bazel's cc_library requires directory artifacts in srcs/hdrs to contain only
    # recognized C++ source/header extensions (.cpp, .h, .hpp).
    # We run verilator and then prune non-C++ files.
    run_cmd = """
"{verilator}" "$@"
find "{out_dir}" -type f ! -name "*.cpp" ! -name "*.h" ! -name "*.hpp" -delete
""".format(
        verilator = tc.verilator_path,
        out_dir = out_dir.path,
    )

    ctx.actions.run_shell(
        outputs = [out_dir],
        inputs = depset(dedup_srcs + all_hdrs + dedup_waivers),
        command = run_cmd,
        arguments = args[1:],
        mnemonic = "VerilatorTranspile",
        progress_message = "Verilating %s to C++" % ctx.attr.top,
    )

    return [
        DefaultInfo(files = depset([out_dir])),
        VerilatorCppInfo(
            hdrs = depset([out_dir]),
            srcs = depset([out_dir]),
            top = ctx.attr.top,
        ),
    ]

verilator_transpile = rule(
    implementation = _verilator_transpile_impl,
    doc = "Transpiles SystemVerilog into C++ model sources using Verilator --cc.",
    attrs = {
        "top": attr.string(
            mandatory = True,
            doc = "Top-level SystemVerilog module name.",
        ),
        "srcs": attr.label_list(
            allow_files = [".sv", ".v", ".vlt"],
            default = [],
            doc = "Optional direct source files.",
        ),
        "hdrs": attr.label_list(
            allow_files = [".svh", ".vh", ".h"],
            default = [],
            doc = "Optional direct header files.",
        ),
        "waivers": attr.label_list(
            allow_files = [".vlt"],
            default = [],
            doc = "Verilator .vlt configuration and waiver files.",
        ),
        "deps": attr.label_list(
            providers = [SvInfo],
            default = [],
            doc = "SystemVerilog libraries providing SvInfo.",
            cfg = verilator_transition,
        ),
        "verilator_flags": attr.string_list(
            default = ["-Wall", "-Wno-fatal"],
            doc = "Extra flags passed to verilator.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = [VERILATOR_TOOLCHAIN_TYPE],
)

def verilator_library(
        name,
        top,
        srcs = [],
        hdrs = [],
        deps = [],
        waivers = [],
        verilator_flags = ["-Wall", "-Wno-fatal"],
        copts = [],
        defines = [],
        includes = [],
        alwayslink = False,
        visibility = None,
        **kwargs):
    """Transpiles SystemVerilog with Verilator and builds a reusable C++ library.

    Args:
        name: Name of the C++ library target.
        top: Name of the top-level SystemVerilog module.
        srcs: Optional direct SystemVerilog source files.
        hdrs: Optional direct header files.
        deps: sv_library dependencies providing SystemVerilog sources.
        waivers: Verilator .vlt configuration and waiver files.
        verilator_flags: Flags passed to the Verilator transpiler.
        copts: C++ compiler options.
        defines: Preprocessor defines for C++ compilation.
        includes: Include directories for C++ compilation.
        alwayslink: Whether to link all object files from this library unconditionally.
        visibility: Target visibility.
        **kwargs: Additional attributes passed to cc_library.
    """
    gen_target = name + "_gen"
    model_dir = gen_target + "_dir"

    verilator_transpile(
        name = gen_target,
        top = top,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        waivers = waivers,
        verilator_flags = verilator_flags,
        visibility = ["//visibility:private"],
    )

    cc_library(
        name = name,
        srcs = [":" + gen_target],
        hdrs = [":" + gen_target],
        includes = [model_dir] + includes,
        deps = [
            "@verilator_default//:runtime",
        ],
        copts = [
            "-std=c++20",
            "-Wno-aligned-new",
            "-Wno-sign-compare",
            "-Wno-unused-parameter",
            "-Wno-unused-variable",
        ] + copts,
        defines = defines,
        alwayslink = alwayslink,
        visibility = visibility,
        **kwargs
    )
