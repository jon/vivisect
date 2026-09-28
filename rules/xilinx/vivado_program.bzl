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

"""AMD Vivado FPGA programming executable rule with TargetLock concurrency control."""

load("//rules:providers.bzl", "VivadoBitstreamInfo")

VIVADO_TOOLCHAIN_TYPE = Label("//rules/toolchains:vivado_toolchain_type")

def _vivado_program_impl(ctx):
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

    runner_sh = ctx.actions.declare_file(ctx.label.name + ".sh")

    runner_path = ctx.file.runner.short_path
    lock_path = ctx.file.target_lock.short_path
    isolated_runner_path = tc.isolated_runner.short_path
    bit_path = bit_file.short_path
    probes_path = probes_file.short_path if probes_file else ""

    pre_paths = " ".join(["--tcl-pre \"%s\"" % p.short_path for p in ctx.files.tcl_pre])
    post_paths = " ".join(["--tcl-post \"%s\"" % p.short_path for p in ctx.files.tcl_post])

    flash_flag = "--flash" if ctx.attr.flash else ""
    flash_part_arg = "--flash-part \"%s\"" % ctx.attr.flash_part if ctx.attr.flash_part else ""

    sh_content = """#!/usr/bin/env bash
set -euo pipefail

# Resolve runfiles directory
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
    {pre_paths} \\
    {post_paths} \\
    {flash_flag} \\
    {flash_part_arg} \\
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
        pre_paths = pre_paths,
        post_paths = post_paths,
        flash_flag = flash_flag,
        flash_part_arg = flash_part_arg,
    )

    ctx.actions.write(
        output = runner_sh,
        content = sh_content,
        is_executable = True,
    )

    runfiles_files = [
        ctx.file.runner,
        ctx.file.target_lock,
        tc.isolated_runner,
        bit_file,
    ]
    if probes_file:
        runfiles_files.append(probes_file)
    runfiles_files.extend(ctx.files.tcl_pre)
    runfiles_files.extend(ctx.files.tcl_post)

    return [
        DefaultInfo(
            executable = runner_sh,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

vivado_program = rule(
    implementation = _vivado_program_impl,
    executable = True,
    doc = "Programs an FPGA bitstream (.bit) onto target hardware via Vivado Hardware Manager.",
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
        "flash": attr.bool(
            default = False,
            doc = "Program SPI configuration flash memory instead of volatile SRAM.",
        ),
        "flash_part": attr.string(
            default = "",
            doc = "SPI configuration flash memory part string (e.g. 's25fl128s-3.3v-spi-x1_x2_x4').",
        ),
        "tcl_pre": attr.label_list(
            allow_files = [".tcl"],
            default = [],
            doc = "Tcl scripts sourced prior to program_hw_devices.",
        ),
        "tcl_post": attr.label_list(
            allow_files = [".tcl"],
            default = [],
            doc = "Tcl scripts sourced after successful programming.",
        ),
        "runner": attr.label(
            default = Label("//rules/support:hw_program_runner.py"),
            allow_single_file = True,
            doc = "Internal programming runner script.",
        ),
        "target_lock": attr.label(
            default = Label("//rules/support:target_lock.py"),
            allow_single_file = True,
            doc = "Internal TargetLock module.",
        ),
    },
    toolchains = [VIVADO_TOOLCHAIN_TYPE],
)
