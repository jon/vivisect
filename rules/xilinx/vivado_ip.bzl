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

"""AMD Vivado IP Catalog rule generating checkpoints, black-box stubs, and simulation netlists."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//rules:providers.bzl",
    "SvInfo",
    "VivadoBoardInfo",
    "VivadoDcpInfo",
    "VivadoPartInfo",
)

VIVADO_TOOLCHAIN_TYPE = Label("//rules/toolchains:vivado_toolchain_type")

def _vivado_ip_impl(ctx):
    tc = ctx.toolchains[VIVADO_TOOLCHAIN_TYPE].vivado

    part_str = ""
    if ctx.attr.part:
        part_str = ctx.attr.part[VivadoPartInfo].part
    elif ctx.attr.board:
        if VivadoBoardInfo in ctx.attr.board:
            part_str = ctx.attr.board[VivadoBoardInfo].part
        elif VivadoPartInfo in ctx.attr.board:
            part_str = ctx.attr.board[VivadoPartInfo].part
    if not part_str:
        fail("vivado_ip target '%s' requires either a 'part' or 'board' attribute." % ctx.label)

    mod_name = ctx.attr.module_name if ctx.attr.module_name else ctx.label.name

    dcp_file = ctx.actions.declare_file(ctx.label.name + ".dcp")
    stub_file = ctx.actions.declare_file(ctx.label.name + "_stub.v")
    sim_file = ctx.actions.declare_file(ctx.label.name + "_sim_netlist.v")
    log_file = ctx.actions.declare_file(ctx.label.name + ".log")
    ip_script = ctx.actions.declare_file(ctx.label.name + "_gen_ip.tcl")

    tcl_lines = [
        "if {[catch {",
        "    set part \"%s\"" % part_str,
        "    set mod_name \"%s\"" % mod_name,
        "    create_project -in_memory -part $part",
    ]

    create_ip_cmd = [
        "create_ip",
        "-name", ctx.attr.ip_name,
        "-vendor", ctx.attr.vendor,
        "-library", ctx.attr.library,
        "-module_name", "$mod_name",
    ]
    if ctx.attr.version:
        create_ip_cmd.extend(["-version", ctx.attr.version])

    tcl_lines.append("    " + " ".join(create_ip_cmd))

    if ctx.attr.config:
        props = []
        for k, v in ctx.attr.config.items():
            props.append("%s {%s}" % (k, v))
        tcl_lines.extend([
            "    set raw_props [list %s]" % " ".join(props),
            "    set resolved_props [list]",
            "    foreach {prop val} $raw_props {",
            "        if {[file exists $val]} {",
            "            set val [file normalize $val]",
            "        }",
            "        lappend resolved_props $prop $val",
            "    }",
            "    set_property -dict $resolved_props [get_ips $mod_name]",
        ])

    tcl_lines.extend([
        "    generate_target {synthesis simulation} [get_ips $mod_name]",
        "    synth_ip [get_ips $mod_name]",
        "    if {[file exists .gen/sources_1/ip/$mod_name/$mod_name.dcp]} {",
        "        file copy -force .gen/sources_1/ip/$mod_name/$mod_name.dcp ip.dcp",
        "    } else {",
        "        write_checkpoint -force ip.dcp",
        "    }",
        "    if {[file exists .gen/sources_1/ip/$mod_name/${mod_name}_stub.v]} {",
        "        file copy -force .gen/sources_1/ip/$mod_name/${mod_name}_stub.v ip_stub.v",
        "    } else {",
        "        write_verilog -mode synth_stub -force ip_stub.v",
        "    }",
        "    if {[file exists .gen/sources_1/ip/$mod_name/${mod_name}_sim_netlist.v]} {",
        "        file copy -force .gen/sources_1/ip/$mod_name/${mod_name}_sim_netlist.v ip_sim_netlist.v",
        "    } else {",
        "        write_verilog -mode funcsim -force ip_sim_netlist.v",
        "    }",
        "} err]} {",
        "    puts stderr \"ERROR: IP generation failed: $err\"",
        "    puts stderr $::errorInfo",
        "    exit 1",
        "}",
    ])

    ctx.actions.write(
        output = ip_script,
        content = "\n".join(tcl_lines) + "\n",
    )

    runner_args = [
        tc.isolated_runner.path,
        "--action-name", ctx.label.name,
        "--log-file", log_file.path,
        "--copy-output", "ip.dcp:" + dcp_file.path,
        "--sanitize-verilog-output", "ip_stub.v:" + stub_file.path,
        "--sanitize-verilog-output", "ip_sim_netlist.v:" + sim_file.path,
    ]

    for extra in ctx.files.extra_inputs:
        runner_args.extend(["--copy-input", "%s:%s" % (extra.path, extra.basename)])

    runner_args.extend([
        "--",
        tc.vivado_path,
        "-mode", "batch",
        "-nojournal",
        "-nolog",
        "-source", ip_script.path,
    ])

    exec_reqs = {}
    if ctx.attr.local:
        exec_reqs["no-sandbox"] = "1"

    ctx.actions.run(
        outputs = [dcp_file, stub_file, sim_file, log_file],
        inputs = depset([ip_script] + ctx.files.extra_inputs, transitive = [depset([tc.isolated_runner])]),
        executable = tc.isolated_runner,
        arguments = runner_args[1:],
        mnemonic = "VivadoIPGen",
        progress_message = "Generating Vivado IP %s (%s)" % (ctx.attr.ip_name, mod_name),
        execution_requirements = exec_reqs,
    )

    stage_val = ctx.attr._stage[BuildSettingInfo].value
    if stage_val == "simulation":
        chosen_sv_srcs = [sim_file]
    else:
        chosen_sv_srcs = [stub_file]

    return [
        DefaultInfo(files = depset([dcp_file, stub_file, sim_file, log_file])),
        VivadoDcpInfo(
            dcp = dcp_file,
            top = mod_name,
            stage = "synth",
            reports = {},
            stub = stub_file,
            part = part_str,
            out_of_context = True,
            cells = {},
        ),
        SvInfo(
            srcs = depset(chosen_sv_srcs),
            hdrs = depset([]),
            includes = depset([]),
            defines = depset([]),
            pkgs = depset([]),
            interfaces = depset([]),
            modules = depset(chosen_sv_srcs),
            data = depset([]),
            waivers = depset([]),
            transitive_srcs = depset(chosen_sv_srcs),
        ),
    ]

vivado_ip = rule(
    implementation = _vivado_ip_impl,
    doc = "Generates an IP core from AMD Vivado IP catalog, producing DCP, stub, and simulation netlists.",
    attrs = {
        "ip_name": attr.string(
            mandatory = True,
            doc = "Name of IP in catalog (e.g. 'clk_wiz', 'c_addsub').",
        ),
        "module_name": attr.string(
            default = "",
            doc = "Generated module name (defaults to target name).",
        ),
        "vendor": attr.string(
            default = "xilinx.com",
            doc = "IP vendor (defaults to 'xilinx.com').",
        ),
        "library": attr.string(
            default = "ip",
            doc = "IP library (defaults to 'ip').",
        ),
        "version": attr.string(
            default = "",
            doc = "IP catalog version string (defaults to latest).",
        ),
        "part": attr.label(
            providers = [VivadoPartInfo],
            doc = "Target FPGA part (vivado_part).",
        ),
        "board": attr.label(
            doc = "Target FPGA development board (vivado_board).",
        ),
        "config": attr.string_dict(
            default = {},
            doc = "IP core CONFIG properties dictionary.",
        ),
        "extra_inputs": attr.label_list(
            allow_files = True,
            default = [],
            doc = "External data/configuration files needed during IP generation, such as MIG .prj or BRAM .coe files.",
        ),
        "local": attr.bool(
            default = False,
            doc = "Execute locally without sandbox.",
        ),
        "_stage": attr.label(
            default = "//rules:stage",
        ),
    },
    toolchains = [VIVADO_TOOLCHAIN_TYPE],
)
