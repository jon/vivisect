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

"""AMD xelab elaboration rule generating simulation snapshot artifacts."""

load("//rules:providers.bzl", "SvInfo", "XsimSnapshotInfo")
load("//rules:stage.bzl", "simulation_transition")

VIVADO_TOOLCHAIN_TYPE = Label("//rules/toolchains:vivado_toolchain_type")

def _xelab_impl(ctx):
    tc = ctx.toolchains[VIVADO_TOOLCHAIN_TYPE].vivado
    snapshot = ctx.attr.snapshot_name if ctx.attr.snapshot_name else ctx.attr.top + "_snap"
    out_dir = ctx.actions.declare_directory(ctx.label.name + "_dir")

    dep_pkgs = []
    dep_interfaces = []
    dep_modules = []
    all_hdrs = []
    all_data = []
    all_includes = []
    all_defines = []

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
            if hasattr(info, "data") and info.data:
                all_data.extend(info.data.to_list())

    ordered_pkgs = depset(order = "postorder", transitive = dep_pkgs).to_list()
    ordered_interfaces = depset(order = "postorder", transitive = dep_interfaces).to_list()
    ordered_modules = depset(order = "postorder", transitive = dep_modules).to_list()
    direct_srcs = [s for s in ctx.files.srcs if s.path.endswith(".sv") or s.path.endswith(".v")]

    all_srcs = ordered_pkgs + ordered_interfaces + ordered_modules + direct_srcs
    all_hdrs.extend(ctx.files.hdrs)
    all_data.extend(ctx.files.data)

    # De-duplicate sources preserving order
    seen_srcs = {}
    dedup_srcs = []
    for s in all_srcs:
        if s.path not in seen_srcs:
            seen_srcs[s.path] = True
            dedup_srcs.append(s)

    copy_dir_arg = "xsim.dir:" + out_dir.path + "/xsim.dir"
    log_file = ctx.actions.declare_file(ctx.label.name + ".log")

    effective_tops = [ctx.attr.top] + ctx.attr.tops
    if "unisims_ver" in ctx.attr.libs and "glbl" not in effective_tops:
        effective_tops.append("glbl")

    args = [
        tc.isolated_runner.path,
        "--action-name",
        ctx.label.name,
        "--log-file",
        log_file.path,
        "--copy-dir-output",
        copy_dir_arg,
        "--",
        tc.xelab_path,
    ]

    for t in effective_tops:
        args.extend(["-top", t])

    args.extend([
        "-snapshot",
        snapshot,
        "-debug",
        ctx.attr.debug,
    ])

    for lib in ctx.attr.libs:
        args.extend(["-L", lib])

    for inc in all_includes:
        args.extend(["-i", inc])

    for d in all_defines:
        args.extend(["-d", d])

    args.extend(ctx.attr.xelab_flags)

    for s in dedup_srcs:
        if s.path.endswith(".sv") or s.path.endswith(".v"):
            args.extend(["-svlog", s.path])

    toolchain_inputs = [tc.isolated_runner]
    has_user_glbl = any([s.basename == "glbl.v" for s in dedup_srcs])
    if "glbl" in effective_tops and not has_user_glbl:
        if tc.glbl_src:
            args.extend(["-svlog", tc.glbl_src.path])
            toolchain_inputs.append(tc.glbl_src)
        else:
            fail("Target '%s' requires glbl for simulation elaboration (effective tops: %s), but glbl.v was not found in the Vivado toolchain." % (ctx.label, effective_tops))

    exec_reqs = {}
    if ctx.attr.local:
        exec_reqs["no-sandbox"] = "1"

    ctx.actions.run(
        outputs = [out_dir, log_file],
        inputs = depset(dedup_srcs + all_hdrs + all_data, transitive = [depset(toolchain_inputs)]),
        executable = tc.isolated_runner,
        arguments = args[1:],
        mnemonic = "Xelab",
        progress_message = "Elaborating xsim snapshot %s" % snapshot,
        execution_requirements = exec_reqs,
    )

    return [
        DefaultInfo(files = depset([out_dir, log_file])),
        XsimSnapshotInfo(
            snapshot_dir = out_dir,
            top = ctx.attr.top,
            snapshot_name = snapshot,
        ),
    ]

xelab = rule(
    implementation = _xelab_impl,
    doc = "Elaborates SystemVerilog sources using AMD xelab into a simulation snapshot.",
    attrs = {
        "top": attr.string(
            mandatory = True,
            doc = "Top-level testbench or module name.",
        ),
        "tops": attr.string_list(
            default = [],
            doc = "Additional top-level modules (e.g. 'glbl').",
        ),
        "srcs": attr.label_list(
            allow_files = [".sv", ".v"],
            doc = "Direct SystemVerilog/Verilog source files.",
        ),
        "hdrs": attr.label_list(
            allow_files = [".svh", ".vh"],
            doc = "Direct header files.",
        ),
        "deps": attr.label_list(
            providers = [SvInfo],
            default = [],
            doc = "Dependencies providing SvInfo.",
            cfg = simulation_transition,
        ),
        "snapshot_name": attr.string(
            default = "",
            doc = "Snapshot name (defaults to <top>_snap).",
        ),
        "debug": attr.string(
            default = "typical",
            doc = "Elaboration debug level (typical, off, line, all).",
        ),
        "xelab_flags": attr.string_list(
            default = [],
            doc = "Additional arguments passed to xelab.",
        ),
        "data": attr.label_list(
            allow_files = True,
            default = [],
            doc = "Optional direct data files (.mem, .hex, .dat).",
        ),
        "libs": attr.string_list(
            default = [],
            doc = "Precompiled simulation libraries to bind via -L (e.g. 'unisims_ver', 'unimacro_ver').",
        ),
        "local": attr.bool(
            default = False,
            doc = "Run locally with no-sandbox tag.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = [VIVADO_TOOLCHAIN_TYPE],
)
