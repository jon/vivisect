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

"""Hardware-in-the-loop (HIL) test rule executing assertions against physical FPGAs."""

load("//rules:providers.bzl", "VivadoBitstreamInfo")

VIVADO_TOOLCHAIN_TYPE = Label("//rules/toolchains:vivado_toolchain_type")

def _vivado_hw_test_impl(ctx):
    tc = ctx.toolchains[VIVADO_TOOLCHAIN_TYPE].vivado

    bit_file = None
    probes_file = ctx.file.probes
    part_str = ctx.attr.part

    if VivadoBitstreamInfo in ctx.attr.bitstream:
        binfo = ctx.attr.bitstream[VivadoBitstreamInfo]
        bit_file = binfo.bit
        if not part_str and binfo.part:
            part_str = binfo.part
        if not probes_file and binfo.probes:
            probes_file = binfo.probes
    else:
        for f in ctx.attr.bitstream[DefaultInfo].files.to_list():
            if f.path.endswith(".bit"):
                bit_file = f
                break

    if not bit_file:
        fail("Target '%s' does not provide a .bit bitstream file." % ctx.attr.bitstream.label)

    test_sh = ctx.actions.declare_file(ctx.label.name + ".sh")

    runner_path = ctx.file.runner.short_path
    prog_runner_path = ctx.file.program_runner.short_path
    lock_path = ctx.file.target_lock.short_path
    client_path = ctx.file.hw_client.short_path
    isolated_runner_path = tc.isolated_runner.short_path
    bit_path = bit_file.short_path
    probes_path = probes_file.short_path if probes_file else ""

    skip_prog_arg = "--skip-program" if ctx.attr.skip_program else ""
    mock_arg = "--mock" if ctx.attr.mock else ""

    # Mode resolution
    mode = ctx.attr.mode
    if mode == "done_only":
        if ctx.attr.uart_expect:
            mode = "uart"
        elif ctx.file.tcl_test:
            mode = "tcl"
        elif ctx.executable.test_runner:
            mode = "runner"

    uart_args = []
    if mode == "uart":
        uart_args.append("--uart-port \"%s\"" % ctx.attr.uart_port)
        uart_args.append("--uart-baud %d" % ctx.attr.uart_baud)
        uart_args.append("--uart-timeout %s" % ctx.attr.uart_timeout)
        if ctx.attr.uart_send:
            uart_args.append("--uart-send \"%s\"" % ctx.attr.uart_send)
        for exp in ctx.attr.uart_expect:
            uart_args.append("--uart-expect \"%s\"" % exp)

    tcl_test_path = ctx.file.tcl_test.short_path if ctx.file.tcl_test else ""
    tcl_args = "--tcl-test $(resolve_file \"%s\")" % tcl_test_path if tcl_test_path else ""

    runner_test_path = ctx.executable.test_runner.short_path if ctx.executable.test_runner else ""
    custom_runner_args = "--test-runner $(resolve_file \"%s\")" % runner_test_path if runner_test_path else ""

    sh_content = """#!/usr/bin/env bash
set -euo pipefail

resolve_file() {{
    local rel="$1"
    if [ -n "${{RUNFILES_DIR:-}}" ] && [ -f "${{RUNFILES_DIR}}/${{TEST_WORKSPACE:-_main}}/${{rel}}" ]; then
        echo "${{RUNFILES_DIR}}/${{TEST_WORKSPACE:-_main}}/${{rel}}"
    elif [ -d "${{BASH_SOURCE[0]}}.runfiles" ] && [ -f "${{BASH_SOURCE[0]}}.runfiles/${{TEST_WORKSPACE:-_main}}/${{rel}}" ]; then
        echo "${{BASH_SOURCE[0]}}.runfiles/${{TEST_WORKSPACE:-_main}}/${{rel}}"
    elif [ -f "${{rel}}" ]; then
        echo "${{rel}}"
    else
        echo "${{rel}}"
    fi
}}

RUNNER=$(resolve_file "{runner_path}")
ISOLATED_RUNNER=$(resolve_file "{isolated_runner_path}")
BITSTREAM=$(resolve_file "{bit_path}")

PROBES_ARG=""
if [ -n "{probes_path}" ]; then
    PROBES_ARG="--probes $(resolve_file "{probes_path}")"
fi

exec python3 "$RUNNER" \\
    --bitstream "$BITSTREAM" \\
    $PROBES_ARG \\
    --part "{part_str}" \\
    --device "{device}" \\
    --target "{target_name}" \\
    --url "{hw_server_url}" \\
    --vivado-bin "{vivado_path}" \\
    --isolated-runner "$ISOLATED_RUNNER" \\
    --lock-timeout "{lock_timeout}" \\
    --mode "{mode}" \\
    {uart_args_str} \\
    {tcl_args} \\
    {custom_runner_args} \\
    {skip_prog_arg} \\
    {mock_arg} \\
    "$@"
""".format(
        runner_path = runner_path,
        isolated_runner_path = isolated_runner_path,
        bit_path = bit_path,
        probes_path = probes_path,
        part_str = part_str,
        device = ctx.attr.device,
        target_name = ctx.attr.target_name,
        hw_server_url = ctx.attr.hw_server_url,
        vivado_path = tc.vivado_path,
        lock_timeout = ctx.attr.lock_timeout,
        mode = mode,
        uart_args_str = " \\\n    ".join(uart_args),
        tcl_args = tcl_args,
        custom_runner_args = custom_runner_args,
        skip_prog_arg = skip_prog_arg,
        mock_arg = mock_arg,
    )

    ctx.actions.write(
        output = test_sh,
        content = sh_content,
        is_executable = True,
    )

    runfiles_files = [
        ctx.file.runner,
        ctx.file.program_runner,
        ctx.file.target_lock,
        ctx.file.hw_client,
        tc.isolated_runner,
        bit_file,
    ]
    if probes_file:
        runfiles_files.append(probes_file)
    if ctx.file.tcl_test:
        runfiles_files.append(ctx.file.tcl_test)
    if ctx.executable.test_runner:
        runfiles_files.append(ctx.executable.test_runner)
    runfiles_files.extend(ctx.files.data)

    return [
        DefaultInfo(
            executable = test_sh,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

_vivado_hw_test = rule(
    implementation = _vivado_hw_test_impl,
    test = True,
    doc = "Executes hardware-in-the-loop test against programmed FPGA device.",
    attrs = {
        "bitstream": attr.label(
            mandatory = True,
            doc = "FPGA bitstream target (vivado_bitstream) or file.",
        ),
        "probes": attr.label(
            allow_single_file = [".ltx"],
            default = None,
            doc = "Optional ILA/VIO debug probes file (.ltx).",
        ),
        "part": attr.string(
            default = "",
            doc = "Target FPGA canonical part string (auto-detected from bitstream if omitted).",
        ),
        "device": attr.string(
            default = "",
            doc = "Target hw_device name or pattern (e.g. 'xc7a100t_0').",
        ),
        "target_name": attr.string(
            default = "",
            doc = "Target hw_target name or cable serial filter (e.g. '210319AE1CDCA').",
        ),
        "hw_server_url": attr.string(
            default = "localhost:3121",
            doc = "AMD hw_server URL (default 'localhost:3121').",
        ),
        "lock_timeout": attr.int(
            default = 60,
            doc = "TargetLock timeout in seconds for device mutual exclusion.",
        ),
        "skip_program": attr.bool(
            default = False,
            doc = "Skip bitstream programming phase.",
        ),
        "mode": attr.string(
            default = "done_only",
            doc = "Test assertion mode: 'done_only', 'uart', 'tcl', or 'runner'.",
        ),
        "uart_port": attr.string(
            default = "auto",
            doc = "Target UART serial port path or 'auto' for FTDI/Digilent auto-detection.",
        ),
        "uart_baud": attr.int(
            default = 115200,
            doc = "UART baud rate (default 115200).",
        ),
        "uart_timeout": attr.string(
            default = "15.0",
            doc = "Maximum seconds to wait for UART patterns.",
        ),
        "uart_expect": attr.string_list(
            default = [],
            doc = "Expected string or regex patterns from serial port.",
        ),
        "uart_send": attr.string(
            default = "",
            doc = "Optional stimulus string to transmit over UART upon connection.",
        ),
        "tcl_test": attr.label(
            allow_single_file = [".tcl"],
            default = None,
            doc = "Optional Vivado Hardware Manager Tcl test script.",
        ),
        "test_runner": attr.label(
            executable = True,
            cfg = "target",
            default = None,
            doc = "Optional custom test executable or script.",
        ),
        "data": attr.label_list(
            allow_files = True,
            default = [],
            doc = "Supporting test data files.",
        ),
        "mock": attr.bool(
            default = False,
            doc = "Simulate test without hardware for CI validation.",
        ),
        "runner": attr.label(
            default = Label("//rules/support:hw_test_runner.py"),
            allow_single_file = True,
            doc = "Internal HIL test harness script.",
        ),
        "program_runner": attr.label(
            default = Label("//rules/support:hw_program_runner.py"),
            allow_single_file = True,
            doc = "Internal programming runner script.",
        ),
        "target_lock": attr.label(
            default = Label("//rules/support:target_lock.py"),
            allow_single_file = True,
            doc = "Internal TargetLock module.",
        ),
        "hw_client": attr.label(
            default = Label("//rules/support:hw_client.py"),
            allow_single_file = True,
            doc = "Internal UartClient module.",
        ),
    },
    toolchains = [VIVADO_TOOLCHAIN_TYPE],
)

def vivado_hw_test(
        name,
        bitstream,
        tags = [],
        mock = False,
        **kwargs):
    """Executes a hardware-in-the-loop test against physical FPGA hardware.

    Defaults to tags = ["manual", "local", "exclusive"] so tests requiring
    physical hardware are not run during wildcard 'bazel test //...' on machines
    without hardware, but run exclusively when requested.

    Args:
        name: Name of the test target.
        bitstream: FPGA bitstream target (vivado_bitstream) or file.
        tags: Additional tags passed to test target.
        mock: If True, runs in simulated mock mode without hardware (can omit manual tag).
        **kwargs: Other attributes passed to _vivado_hw_test.
    """
    effective_tags = list(tags)
    if not mock:
        if "manual" not in effective_tags:
            effective_tags.append("manual")
    if "local" not in effective_tags:
        effective_tags.append("local")
    if "exclusive" not in effective_tags:
        effective_tags.append("exclusive")

    _vivado_hw_test(
        name = name,
        bitstream = bitstream,
        mock = mock,
        tags = effective_tags,
        **kwargs
    )
