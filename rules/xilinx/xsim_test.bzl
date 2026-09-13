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

"""AMD xsim simulation test rule with native Tcl-based deterministic error trapping."""

load("//rules:providers.bzl", "SvInfo", "XsimSnapshotInfo")
load(":xelab.bzl", "xelab")

VIVADO_TOOLCHAIN_TYPE = Label("//rules/toolchains:vivado_toolchain_type")

def _xsim_test_rule_impl(ctx):
    tc = ctx.toolchains[VIVADO_TOOLCHAIN_TYPE].vivado
    snap_info = ctx.attr.snapshot[XsimSnapshotInfo]
    snap_dir = snap_info.snapshot_dir
    snap_name = snap_info.snapshot_name

    tcl_script = ctx.actions.declare_file(ctx.label.name + "_driver.tcl")
    test_sh = ctx.actions.declare_file(ctx.label.name + ".sh")

    # Build Tcl simulation driver
    tcl_lines = [
        "# Vivisect auto-generated xsim driver for %s" % ctx.label,
    ]

    if ctx.attr.waveforms:
        tcl_lines.append("log_wave -r /")

    for pre in ctx.files.tcl_pre:
        tcl_lines.append("source %s" % pre.short_path)

    tcl_lines.append("run all")

    if ctx.attr.waveforms:
        tcl_lines.append("catch {flush_wave}")

    for post in ctx.files.tcl_post:
        tcl_lines.append("source %s" % post.short_path)

    fail_on_error_val = "1" if ctx.attr.fail_on_error else "0"

    tcl_lines.append("""
set log_file "xsim.log"
set sim_failed 0
set failure_reasons [list]

if {[file exists $log_file]} {
    set fp [open $log_file r]
    set log_data [read $fp]
    close $fp

    # Structural specification of simulator kernel diagnostic metadata line
    set time_meta {Time:\\s*\\d+\\s*(?:fs|ps|ns|us|ms|s)\\s+Iteration:\\s*\\d+\\s+Process:\\s*\\S+(?:\\s+Scope:\\s*\\S+)?(?:\\s+File:\\s*\\S+\\s+Line:\\s*\\d+)?}

    # 1. Matches authentic $fatal block:
    set fatal_pattern "(?m)^Fatal:.*\\[\\\\r\\\\n\\]+(?:.*\\[\\\\r\\\\n\\]+)*?${time_meta}"
    if {[regexp $fatal_pattern $log_data]} {
        set sim_failed 1
        lappend failure_reasons "SystemVerilog \\$fatal condition detected"
    }

    # 2. Matches authentic $error or assertion violation block:
    set error_pattern "(?m)^Error:.*\\[\\\\r\\\\n\\]+(?:.*\\[\\\\r\\\\n\\]+)*?${time_meta}"
    if {%s && [regexp $error_pattern $log_data]} {
        set sim_failed 1
        lappend failure_reasons "SystemVerilog \\$error or assertion violation detected"
    }
} else {
    set sim_failed 1
    lappend failure_reasons "xsim.log was not generated"
}

if {$sim_failed} {
    puts "================================================================"
    puts " Vivisect xsim_test: SIMULATION FAILED"
    foreach reason $failure_reasons {
        puts "   * $reason"
    }
    puts "================================================================"
    exit 1
} else {
    puts "Vivisect xsim_test: Simulation completed cleanly."
    exit 0
}
""" % fail_on_error_val)

    ctx.actions.write(
        output = tcl_script,
        content = "\n".join(tcl_lines) + "\n",
    )

    # Runner command invoking run_isolated.py with writable copy of xsim.dir
    runner_cmd = [
        tc.isolated_runner.short_path,
        "--action-name",
        ctx.label.name,
        "--verbose",
        "--copy-input-dir",
        "%s/xsim.dir:xsim.dir" % snap_dir.short_path,
    ]

    if ctx.attr.waveforms:
        wdb_name = snap_name + ".wdb"
        runner_cmd.extend([
            "--copy-output",
            "%s:${TEST_UNDECLARED_OUTPUTS_DIR:-.}/%s.wdb" % (wdb_name, ctx.label.name),
        ])

    runner_cmd.extend([
        "--",
        tc.xsim_path,
        snap_name,
        "-tclbatch",
        tcl_script.short_path,
    ])

    if ctx.attr.waveforms:
        runner_cmd.extend(["--wdb", snap_name + ".wdb"])

    runner_cmd.extend(ctx.attr.xsim_flags)

    sh_content = """#!/usr/bin/env bash
set -euo pipefail

exec {cmd}
""".format(
        cmd = " ".join(runner_cmd),
    )

    ctx.actions.write(
        output = test_sh,
        content = sh_content,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [tc.isolated_runner, tcl_script] + ctx.files.tcl_pre + ctx.files.tcl_post + ctx.files.data,
        transitive_files = depset([snap_dir]),
    )

    return [
        DefaultInfo(
            executable = test_sh,
            runfiles = runfiles,
        ),
    ]

_xsim_test = rule(
    implementation = _xsim_test_rule_impl,
    test = True,
    doc = "Executes an elaborated simulation snapshot under xsim with native Tcl error trapping.",
    attrs = {
        "snapshot": attr.label(
            providers = [XsimSnapshotInfo],
            mandatory = True,
            doc = "Elaborated simulation snapshot target from xelab.",
        ),
        "waveforms": attr.bool(
            default = False,
            doc = "Capture waveform database (.wdb) in test undeclared outputs.",
        ),
        "fail_on_error": attr.bool(
            default = True,
            doc = "Whether SystemVerilog $error / assertion violations trigger test failure.",
        ),
        "data": attr.label_list(
            allow_files = True,
            default = [],
            doc = "Supporting data and memory initialization files (.mem, .hex, .dat).",
        ),
        "tcl_pre": attr.label_list(
            allow_files = [".tcl"],
            doc = "Tcl scripts executed prior to run all.",
        ),
        "tcl_post": attr.label_list(
            allow_files = [".tcl"],
            doc = "Tcl scripts executed after run all.",
        ),
        "xsim_flags": attr.string_list(
            default = [],
            doc = "Additional arguments passed to xsim.",
        ),
    },
    toolchains = [VIVADO_TOOLCHAIN_TYPE],
)

def xsim_test(
        name,
        top,
        srcs = [],
        hdrs = [],
        deps = [],
        data = [],
        tops = [],
        libs = [],
        snapshot_name = "",
        debug = "typical",
        xelab_flags = [],
        xsim_flags = [],
        waveforms = False,
        fail_on_error = True,
        tcl_pre = [],
        tcl_post = [],
        local = False,
        tags = [],
        **kwargs):
    """Macro that elaborates SystemVerilog with xelab and executes xsim simulation.

    Args:
        name: Name of the test target.
        top: Top-level testbench or module name.
        tops: Additional top-level modules (e.g. 'glbl').
        srcs: Direct SystemVerilog/Verilog source files.
        hdrs: Direct header files.
        deps: Dependencies providing SvInfo.
        data: Direct data and memory initialization files (.mem, .hex, .dat).
        libs: Precompiled simulation libraries to bind via -L (e.g. 'unisims_ver').
        snapshot_name: Optional custom snapshot name.
        debug: Elaboration debug level (typical, off, line, all).
        xelab_flags: Extra arguments for xelab.
        xsim_flags: Extra arguments for xsim.
        waveforms: Whether to retain waveform database artifact.
        fail_on_error: Whether $error and assertion violations cause test failure.
        tcl_pre: Tcl scripts executed before run all.
        tcl_post: Tcl scripts executed after run all.
        local: Whether to execute locally without sandbox.
        tags: Test tags passed to test target.
        **kwargs: Common test attributes passed to _xsim_test.
    """
    snap_target = name + "_snapshot"

    xelab(
        name = snap_target,
        top = top,
        tops = tops,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        data = data,
        libs = libs,
        snapshot_name = snapshot_name,
        debug = debug,
        xelab_flags = xelab_flags,
        local = local,
    )

    # Node-locked AMD licenses bound to MAC address need network namespace visibility
    effective_tags = ["requires-network"] + tags
    if local:
        effective_tags.append("local")

    _xsim_test(
        name = name,
        snapshot = ":" + snap_target,
        waveforms = waveforms,
        fail_on_error = fail_on_error,
        data = data,
        tcl_pre = tcl_pre,
        tcl_post = tcl_post,
        xsim_flags = xsim_flags,
        tags = effective_tags,
        **kwargs
    )
