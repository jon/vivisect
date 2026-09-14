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

"""AMD Vivado synthesis rule supporting out-of-context stubs, cells linking, and utilization reports."""

load(
    "//rules:providers.bzl",
    "SvInfo",
    "VivadoBoardInfo",
    "VivadoConstraintsInfo",
    "VivadoDcpInfo",
    "VivadoPartInfo",
)
load("//rules:stage.bzl", "synthesis_transition")

VIVADO_TOOLCHAIN_TYPE = Label("//rules/toolchains:vivado_toolchain_type")

def _vivado_synth_impl(ctx):
    tc = ctx.toolchains[VIVADO_TOOLCHAIN_TYPE].vivado

    # 1. Resolve Part
    part_str = ""
    if ctx.attr.part:
        part_str = ctx.attr.part[VivadoPartInfo].part
    elif ctx.attr.board:
        if VivadoBoardInfo in ctx.attr.board:
            part_str = ctx.attr.board[VivadoBoardInfo].part
        elif VivadoPartInfo in ctx.attr.board:
            part_str = ctx.attr.board[VivadoPartInfo].part
    if not part_str:
        fail("vivado_synth target '%s' requires either a 'part' or 'board' attribute." % ctx.label)

    # 2. Collect SystemVerilog / Verilog sources and data files
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
    all_includes.extend(ctx.attr.includes)
    all_defines.extend(ctx.attr.defines)

    seen_srcs = {}
    dedup_srcs = []
    for s in all_srcs:
        if s.path not in seen_srcs:
            seen_srcs[s.path] = True
            dedup_srcs.append(s)

    # 3. Collect Constraints
    synth_xdc = []
    scoped_xdc = []

    # From board
    if ctx.attr.board and VivadoBoardInfo in ctx.attr.board:
        b_info = ctx.attr.board[VivadoBoardInfo]
        synth_xdc.extend(b_info.constraints.synth_constraints.to_list())
        scoped_xdc.extend(b_info.constraints.scoped_constraints.to_list())

    # From direct xdc attribute
    for item in ctx.attr.xdc:
        if VivadoConstraintsInfo in item:
            c_info = item[VivadoConstraintsInfo]
            synth_xdc.extend(c_info.synth_constraints.to_list())
            scoped_xdc.extend(c_info.scoped_constraints.to_list())
        else:
            synth_xdc.extend(item.files.to_list())

    seen_xdc = {}
    dedup_xdc = []
    for x in synth_xdc:
        if x.path not in seen_xdc:
            seen_xdc[x.path] = True
            dedup_xdc.append(x)

    # 4. Resolve Cells (hierarchical OOC children)
    cell_dcps = {}
    cell_stubs = []
    cell_inputs = []

    for cell_name, cell_target in ctx.attr.cells.items():
        if VivadoDcpInfo not in cell_target:
            fail("Cell target '%s' must provide VivadoDcpInfo." % cell_target.label)
        d_info = cell_target[VivadoDcpInfo]
        cell_dcps[cell_name] = d_info.dcp
        cell_inputs.append(d_info.dcp)
        if d_info.stub:
            cell_stubs.append(d_info.stub)
            cell_inputs.append(d_info.stub)
        elif not d_info.out_of_context:
            fail("Cell '%s' target '%s' must be an out-of-context checkpoint." % (cell_name, cell_target.label))

    # 5. Declare Outputs
    dcp_file = ctx.actions.declare_file(ctx.label.name + ".dcp")
    util_json_file = ctx.actions.declare_file(ctx.label.name + "_utilization.json")
    util_rpt_file = ctx.actions.declare_file(ctx.label.name + "_utilization.rpt")
    log_file = ctx.actions.declare_file(ctx.label.name + ".log")
    stub_file = ctx.actions.declare_file(ctx.label.name + "_stub.v") if ctx.attr.out_of_context else None

    # 6. Generate Synthesis Tcl Script
    tcl_lines = [
        "if {[catch {",
        "    set part \"%s\"" % part_str,
        "    set top \"%s\"" % ctx.attr.top,
        "    create_project -in_memory -part $part",
    ]

    # Add RTL sources
    for s in dedup_srcs:
        if s.path.endswith(".sv"):
            tcl_lines.append("    read_verilog -sv \"%s\"" % s.path)
        elif s.path.endswith(".v"):
            tcl_lines.append("    read_verilog \"%s\"" % s.path)

    # Add cell black box stubs
    for st in cell_stubs:
        tcl_lines.append("    read_verilog \"%s\"" % st.path)

    # Add synthesis constraints
    for x in dedup_xdc:
        tcl_lines.append("    read_xdc \"%s\"" % x.path)

    for sc in scoped_xdc:
        f_path = sc.file.path
        f_name = sc.file.path.split("/")[-1]
        if sc.scoped_to_ref:
            tcl_lines.append("    set_property SCOPED_TO_REF \"%s\" [get_files -quiet [list \"%s\" \"%s\"]]" % (sc.scoped_to_ref, f_path, f_name))
        if sc.scoped_to_cells:
            cells_str = " ".join(sc.scoped_to_cells)
            tcl_lines.append("    set_property SCOPED_TO_CELLS [list %s] [get_files -quiet [list \"%s\" \"%s\"]]" % (cells_str, f_path, f_name))

    # Build synth_design arguments
    synth_cmd_parts = ["synth_design", "-top $top", "-part $part"]
    if ctx.attr.out_of_context:
        synth_cmd_parts.append("-mode out_of_context")
    if ctx.attr.flatten_hierarchy:
        synth_cmd_parts.append("-flatten_hierarchy " + ctx.attr.flatten_hierarchy)
    for inc in all_includes:
        synth_cmd_parts.append("-include_dirs [list \"%s\"]" % inc)
    for d in all_defines:
        synth_cmd_parts.append("-verilog_define \"%s\"" % d)
    for param_name, param_val in ctx.attr.parameters.items():
        synth_cmd_parts.append("-generic {%s=%s}" % (param_name, param_val))
    synth_cmd_parts.extend(ctx.attr.synth_flags)

    tcl_lines.append("    " + " ".join(synth_cmd_parts))

    # If cells are specified, stitch them into the netlist
    if cell_dcps:
        tcl_lines.append("    write_checkpoint -force parent_raw.dcp")
        tcl_lines.append("    close_project")
        tcl_lines.append("    create_project -in_memory -part $part")
        tcl_lines.append("    add_files parent_raw.dcp")
        for c_inst, c_file in cell_dcps.items():
            tcl_lines.append("    read_checkpoint -cell \"%s\" \"%s\"" % (c_inst, c_file.path))
        link_cmd = ["link_design", "-top $top", "-part $part"]
        if ctx.attr.out_of_context:
            link_cmd.append("-mode out_of_context")
        tcl_lines.append("    " + " ".join(link_cmd))

    # Write final checkpoint and reports
    tcl_lines.append("    write_checkpoint -force synth.dcp")
    if ctx.attr.out_of_context:
        tcl_lines.append("    write_verilog -mode synth_stub -force synth_stub.v")
    tcl_lines.append("    report_utilization -json synth_utilization.json")
    tcl_lines.append("    report_utilization -file synth_utilization.rpt")
    tcl_lines.append("} err]} {")
    tcl_lines.append("    puts stderr \"ERROR: Synthesis failed: $err\"")
    tcl_lines.append("    puts stderr $::errorInfo")
    tcl_lines.append("    exit 1")
    tcl_lines.append("}")

    synth_script = ctx.actions.declare_file(ctx.label.name + "_synth.tcl")
    ctx.actions.write(
        output = synth_script,
        content = "\n".join(tcl_lines) + "\n",
    )

    # 7. Execute Action
    runner_args = [
        tc.isolated_runner.path,
        "--action-name", ctx.label.name,
        "--log-file", log_file.path,
        "--copy-output", "synth.dcp:" + dcp_file.path,
        "--copy-output", "synth_utilization.json:" + util_json_file.path,
        "--copy-output", "synth_utilization.rpt:" + util_rpt_file.path,
    ]
    if stub_file:
        runner_args.extend(["--sanitize-verilog-output", "synth_stub.v:" + stub_file.path])

    runner_args.extend([
        "--",
        tc.vivado_path,
        "-mode", "batch",
        "-nojournal",
        "-nolog",
        "-source", synth_script.path,
    ])

    inputs = depset(
        dedup_srcs + all_hdrs + all_data + dedup_xdc + cell_inputs + [synth_script],
        transitive = [depset([tc.isolated_runner])],
    )

    outputs = [dcp_file, util_json_file, util_rpt_file, log_file]
    if stub_file:
        outputs.append(stub_file)

    exec_reqs = {}
    if ctx.attr.local:
        exec_reqs["no-sandbox"] = "1"

    ctx.actions.run(
        outputs = outputs,
        inputs = inputs,
        executable = tc.isolated_runner,
        arguments = runner_args[1:],
        mnemonic = "VivadoSynth",
        progress_message = "Synthesizing %s (%s) with Vivado" % (ctx.attr.top, part_str),
        execution_requirements = exec_reqs,
    )

    # 8. Return Providers
    reports = {
        "utilization_json": util_json_file,
        "utilization": util_rpt_file,
    }

    providers = [
        DefaultInfo(files = depset(outputs)),
        VivadoDcpInfo(
            dcp = dcp_file,
            top = ctx.attr.top,
            stage = "synth",
            reports = reports,
            stub = stub_file,
            part = part_str,
            out_of_context = ctx.attr.out_of_context,
            cells = {k: v[VivadoDcpInfo].dcp for k, v in ctx.attr.cells.items()},
        ),
    ]

    if ctx.attr.out_of_context and stub_file:
        providers.append(
            SvInfo(
                srcs = depset([stub_file]),
                hdrs = depset([]),
                includes = depset([]),
                defines = depset([]),
                pkgs = depset([]),
                interfaces = depset([]),
                modules = depset([stub_file]),
                data = depset([]),
                waivers = depset([]),
                transitive_srcs = depset([stub_file]),
            ),
        )

    return providers

vivado_synth = rule(
    implementation = _vivado_synth_impl,
    doc = "Synthesizes SystemVerilog/Verilog designs using AMD Vivado, supporting hierarchical OOC cell linking.",
    attrs = {
        "top": attr.string(
            mandatory = True,
            doc = "Top-level module name for synthesis.",
        ),
        "part": attr.label(
            providers = [VivadoPartInfo],
            doc = "Target FPGA part (vivado_part).",
        ),
        "board": attr.label(
            doc = "Target FPGA development board (vivado_board).",
        ),
        "srcs": attr.label_list(
            allow_files = [".sv", ".v"],
            default = [],
            doc = "Direct SystemVerilog/Verilog source files.",
        ),
        "hdrs": attr.label_list(
            allow_files = [".svh", ".vh", ".h"],
            default = [],
            doc = "Direct header files.",
        ),
        "deps": attr.label_list(
            providers = [SvInfo],
            default = [],
            doc = "SystemVerilog library dependencies (transitioned to synthesis stage).",
            cfg = synthesis_transition,
        ),
        "cells": attr.string_keyed_label_dict(
            providers = [VivadoDcpInfo],
            default = {},
            doc = "Hierarchical out-of-context cell checkpoints mapped by instance path (e.g. {'u_sub': ':sub_synth'}).",
        ),
        "xdc": attr.label_list(
            allow_files = [".xdc"],
            default = [],
            doc = "Direct XDC files or xdc_library targets.",
        ),
        "out_of_context": attr.bool(
            default = False,
            doc = "Synthesize module out-of-context (OOC), disabling I/O buffer insertion and generating stub.",
        ),
        "flatten_hierarchy": attr.string(
            default = "",
            doc = "Hierarchy flattening strategy ('full', 'none', 'rebuilt').",
        ),
        "synth_flags": attr.string_list(
            default = [],
            doc = "Additional command-line arguments passed to synth_design.",
        ),
        "parameters": attr.string_dict(
            default = {},
            doc = "Top-level module parameter overrides passed to synth_design as -generic.",
        ),
        "data": attr.label_list(
            allow_files = True,
            default = [],
            doc = "Optional direct data files (.mem, .hex, .dat).",
        ),
        "defines": attr.string_list(
            default = [],
            doc = "Preprocessor macro definitions passed to synthesis.",
        ),
        "includes": attr.string_list(
            default = [],
            doc = "Include directories passed to synthesis.",
        ),
        "local": attr.bool(
            default = False,
            doc = "Execute locally without sandbox.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = [VIVADO_TOOLCHAIN_TYPE],
)
