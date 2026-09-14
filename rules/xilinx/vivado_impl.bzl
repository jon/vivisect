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

"""AMD Vivado physical implementation rule (opt, place, phys_opt, route)."""

load(
    "//rules:providers.bzl",
    "VivadoBoardInfo",
    "VivadoConstraintsInfo",
    "VivadoDcpInfo",
    "VivadoPartInfo",
)

VIVADO_TOOLCHAIN_TYPE = Label("//rules/toolchains:vivado_toolchain_type")

def _vivado_impl_impl(ctx):
    tc = ctx.toolchains[VIVADO_TOOLCHAIN_TYPE].vivado
    parent_dcp_info = ctx.attr.checkpoint[VivadoDcpInfo]

    # Resolve part
    part_str = ""
    if ctx.attr.part:
        part_str = ctx.attr.part[VivadoPartInfo].part
    elif ctx.attr.board:
        if VivadoBoardInfo in ctx.attr.board:
            part_str = ctx.attr.board[VivadoBoardInfo].part
        elif VivadoPartInfo in ctx.attr.board:
            part_str = ctx.attr.board[VivadoPartInfo].part
    elif parent_dcp_info.part:
        part_str = parent_dcp_info.part
    if not part_str:
        fail("vivado_impl '%s' could not resolve target FPGA part." % ctx.label)

    # Collect implementation constraints
    impl_xdc = []
    scoped_xdc = []

    if ctx.attr.board and VivadoBoardInfo in ctx.attr.board:
        b_info = ctx.attr.board[VivadoBoardInfo]
        impl_xdc.extend(b_info.constraints.impl_constraints.to_list())
        scoped_xdc.extend(b_info.constraints.scoped_constraints.to_list())

    for item in ctx.attr.xdc:
        if VivadoConstraintsInfo in item:
            c_info = item[VivadoConstraintsInfo]
            impl_xdc.extend(c_info.impl_constraints.to_list())
            scoped_xdc.extend(c_info.scoped_constraints.to_list())
        else:
            impl_xdc.extend(item.files.to_list())

    seen_xdc = {}
    dedup_xdc = []
    for x in impl_xdc:
        if x.path not in seen_xdc:
            seen_xdc[x.path] = True
            dedup_xdc.append(x)

    # Resolve optional cell checkpoints
    cell_dcps = {}
    cell_inputs = []
    for c_inst, c_target in ctx.attr.cells.items():
        c_info = c_target[VivadoDcpInfo]
        cell_dcps[c_inst] = c_info.dcp
        cell_inputs.append(c_info.dcp)

    dcp_file = ctx.actions.declare_file(ctx.label.name + ".dcp")
    timing_file = ctx.actions.declare_file(ctx.label.name + "_timing_summary.rpt")
    util_rpt_file = ctx.actions.declare_file(ctx.label.name + "_utilization.rpt")
    util_json_file = ctx.actions.declare_file(ctx.label.name + "_utilization.json")
    io_file = ctx.actions.declare_file(ctx.label.name + "_io.rpt")
    log_file = ctx.actions.declare_file(ctx.label.name + ".log")
    impl_script = ctx.actions.declare_file(ctx.label.name + "_impl.tcl")

    tcl_lines = [
        "if {[catch {",
        "    set part \"%s\"" % part_str,
        "    create_project -in_memory -part $part",
        "    open_checkpoint \"%s\"" % parent_dcp_info.dcp.path,
    ]

    # Link cell DCPs if specified
    for c_inst, c_file in cell_dcps.items():
        tcl_lines.append("    read_checkpoint -cell \"%s\" \"%s\"" % (c_inst, c_file.path))

    if cell_dcps:
        top_name = parent_dcp_info.top
        tcl_lines.append("    link_design -top \"%s\" -part $part" % top_name)

    # Read implementation constraints
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

    # Opt Design
    opt_cmd = ["opt_design"] + ctx.attr.opt_design_flags
    tcl_lines.append("    " + " ".join(opt_cmd))

    # Place Design
    place_cmd = ["place_design"] + ctx.attr.place_design_flags
    tcl_lines.append("    " + " ".join(place_cmd))

    # Phys Opt Design
    if ctx.attr.run_phys_opt:
        phys_cmd = ["phys_opt_design"] + ctx.attr.phys_opt_design_flags
        tcl_lines.append("    " + " ".join(phys_cmd))

    # Route Design
    route_cmd = ["route_design"] + ctx.attr.route_design_flags
    tcl_lines.append("    " + " ".join(route_cmd))

    # Reports and Output Checkpoint
    tcl_lines.extend([
        "    report_timing_summary -file impl_timing_summary.rpt",
        "    report_utilization -file impl_utilization.rpt",
        "    report_utilization -json impl_utilization.json",
        "    report_io -file impl_io.rpt",
        "    write_checkpoint -force impl.dcp",
        "} err]} {",
        "    puts stderr \"ERROR: Implementation failed: $err\"",
        "    puts stderr $::errorInfo",
        "    exit 1",
        "}",
    ])

    ctx.actions.write(
        output = impl_script,
        content = "\n".join(tcl_lines) + "\n",
    )

    runner_args = [
        tc.isolated_runner.path,
        "--action-name", ctx.label.name,
        "--log-file", log_file.path,
        "--copy-output", "impl.dcp:" + dcp_file.path,
        "--copy-output", "impl_timing_summary.rpt:" + timing_file.path,
        "--copy-output", "impl_utilization.rpt:" + util_rpt_file.path,
        "--copy-output", "impl_utilization.json:" + util_json_file.path,
        "--copy-output", "impl_io.rpt:" + io_file.path,
        "--",
        tc.vivado_path,
        "-mode", "batch",
        "-nojournal",
        "-nolog",
        "-source", impl_script.path,
    ]

    inputs = depset(
        [parent_dcp_info.dcp, impl_script] + dedup_xdc + cell_inputs,
        transitive = [depset([tc.isolated_runner])],
    )

    outputs = [dcp_file, timing_file, util_rpt_file, util_json_file, io_file, log_file]

    exec_reqs = {}
    if ctx.attr.local:
        exec_reqs["no-sandbox"] = "1"

    ctx.actions.run(
        outputs = outputs,
        inputs = inputs,
        executable = tc.isolated_runner,
        arguments = runner_args[1:],
        mnemonic = "VivadoImpl",
        progress_message = "Implementing %s with Vivado" % parent_dcp_info.top,
        execution_requirements = exec_reqs,
    )

    reports = {
        "timing": timing_file,
        "utilization": util_rpt_file,
        "utilization_json": util_json_file,
        "io": io_file,
    }

    return [
        DefaultInfo(files = depset(outputs)),
        VivadoDcpInfo(
            dcp = dcp_file,
            top = parent_dcp_info.top,
            stage = "impl",
            reports = reports,
            stub = None,
            part = part_str,
            out_of_context = False,
            cells = {},
        ),
    ]

vivado_impl = rule(
    implementation = _vivado_impl_impl,
    doc = "Executes Vivado physical implementation (logic optimization, placement, physical optimization, and routing).",
    attrs = {
        "checkpoint": attr.label(
            mandatory = True,
            providers = [VivadoDcpInfo],
            doc = "Input synthesis design checkpoint (vivado_synth target).",
        ),
        "part": attr.label(
            providers = [VivadoPartInfo],
            doc = "Target FPGA part (defaults to checkpoint part).",
        ),
        "board": attr.label(
            doc = "Target FPGA development board (vivado_board).",
        ),
        "xdc": attr.label_list(
            allow_files = [".xdc"],
            default = [],
            doc = "Implementation constraint files or xdc_library targets.",
        ),
        "cells": attr.string_keyed_label_dict(
            providers = [VivadoDcpInfo],
            default = {},
            doc = "Optional cell checkpoints to link during implementation.",
        ),
        "run_phys_opt": attr.bool(
            default = True,
            doc = "Whether to execute phys_opt_design between placement and routing.",
        ),
        "opt_design_flags": attr.string_list(
            default = [],
            doc = "Additional flags passed to opt_design.",
        ),
        "place_design_flags": attr.string_list(
            default = [],
            doc = "Additional flags passed to place_design.",
        ),
        "phys_opt_design_flags": attr.string_list(
            default = [],
            doc = "Additional flags passed to phys_opt_design.",
        ),
        "route_design_flags": attr.string_list(
            default = [],
            doc = "Additional flags passed to route_design.",
        ),
        "local": attr.bool(
            default = False,
            doc = "Execute locally without sandbox.",
        ),
    },
    toolchains = [VIVADO_TOOLCHAIN_TYPE],
)
