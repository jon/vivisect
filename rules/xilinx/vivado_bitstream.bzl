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

"""AMD Vivado bitstream generation rule producing .bit and .bin files."""

load("//rules:providers.bzl", "VivadoBitstreamInfo", "VivadoDcpInfo")

VIVADO_TOOLCHAIN_TYPE = Label("//rules/toolchains:vivado_toolchain_type")

def _vivado_bitstream_impl(ctx):
    tc = ctx.toolchains[VIVADO_TOOLCHAIN_TYPE].vivado
    dcp_info = ctx.attr.checkpoint[VivadoDcpInfo]

    bit_file = ctx.actions.declare_file(ctx.label.name + ".bit")
    bin_file = ctx.actions.declare_file(ctx.label.name + ".bin") if ctx.attr.bin_file else None
    probes_file = ctx.actions.declare_file(ctx.label.name + ".ltx") if ctx.attr.probes else None
    log_file = ctx.actions.declare_file(ctx.label.name + ".log")
    bit_script = ctx.actions.declare_file(ctx.label.name + "_bitstream.tcl")

    tcl_lines = [
        "if {[catch {",
        "    open_checkpoint \"%s\"" % dcp_info.dcp.path,
    ]
    for hook in ctx.files.tcl_hooks:
        tcl_lines.append("    source \"%s\"" % hook.path)
    tcl_lines.append("    set bit_args [list -force bitstream.bit]")
    if ctx.attr.bin_file:
        tcl_lines.append("    lappend bit_args -bin_file")
    for flag in ctx.attr.bitstream_flags:
        tcl_lines.append("    lappend bit_args \"%s\"" % flag)

    if probes_file:
        tcl_lines.append("    catch {write_debug_probes -force probes.ltx}")

    tcl_lines.extend([
        "    write_bitstream {*}$bit_args",
        "} err]} {",
        "    puts stderr \"ERROR: Bitstream generation failed: $err\"",
        "    puts stderr $::errorInfo",
        "    exit 1",
        "}",
    ])

    ctx.actions.write(
        output = bit_script,
        content = "\n".join(tcl_lines) + "\n",
    )

    runner_args = [
        tc.isolated_runner.path,
        "--action-name", ctx.label.name,
        "--log-file", log_file.path,
        "--copy-output", "bitstream.bit:" + bit_file.path,
    ]
    if bin_file:
        runner_args.extend(["--copy-output", "bitstream.bin:" + bin_file.path])
    if probes_file:
        runner_args.extend(["--copy-output", "probes.ltx:" + probes_file.path])

    runner_args.extend([
        "--",
        tc.vivado_path,
        "-mode", "batch",
        "-nojournal",
        "-nolog",
        "-source", bit_script.path,
    ])

    outputs = [bit_file, log_file]
    if bin_file:
        outputs.append(bin_file)
    if probes_file:
        outputs.append(probes_file)

    inputs = depset(
        [dcp_info.dcp, bit_script] + ctx.files.tcl_hooks,
        transitive = [depset([tc.isolated_runner])],
    )

    exec_reqs = {}
    if ctx.attr.local:
        exec_reqs["no-sandbox"] = "1"

    ctx.actions.run(
        outputs = outputs,
        inputs = inputs,
        executable = tc.isolated_runner,
        arguments = runner_args[1:],
        mnemonic = "VivadoBitstream",
        progress_message = "Generating FPGA bitstream for %s" % dcp_info.top,
        execution_requirements = exec_reqs,
    )

    bitstream_info = VivadoBitstreamInfo(
        bit = bit_file,
        bin = bin_file,
        probes = probes_file,
        top = dcp_info.top,
        part = dcp_info.part,
        checkpoint = dcp_info.dcp,
    )

    return [
        DefaultInfo(files = depset(outputs)),
        bitstream_info,
    ]

vivado_bitstream = rule(
    implementation = _vivado_bitstream_impl,
    doc = "Generates an FPGA programming bitstream (.bit) and optional raw flash binary (.bin) with Vivado.",
    attrs = {
        "checkpoint": attr.label(
            mandatory = True,
            providers = [VivadoDcpInfo],
            doc = "Routed implementation checkpoint (vivado_impl target).",
        ),
        "bin_file": attr.bool(
            default = False,
            doc = "Whether to generate a raw binary file (.bin) for SPI flash memory programming.",
        ),
        "probes": attr.bool(
            default = False,
            doc = "Whether to generate an ILA/VIO debug probes file (.ltx).",
        ),
        "bitstream_flags": attr.string_list(
            default = [],
            doc = "Additional flags passed to write_bitstream.",
        ),
        "tcl_hooks": attr.label_list(
            allow_files = [".tcl"],
            default = [],
            doc = "Optional Tcl scripts sourced after opening checkpoint and before write_bitstream.",
        ),
        "local": attr.bool(
            default = False,
            doc = "Execute locally without sandbox.",
        ),
    },
    toolchains = [VIVADO_TOOLCHAIN_TYPE],
)

