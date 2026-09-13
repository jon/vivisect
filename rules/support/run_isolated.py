#!/usr/bin/env python3
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

"""Universal Action Isolation Runner for AMD FPGA Tools and Verilator.

Executes actions inside a disposable, isolated scratch directory within the
Bazel execroot ($PWD/_scratch_<action>_<uuid>). Sanitizes the environment to
prevent user home corruption while preserving floating and node-locked licenses,
redirects logs, stages writable input directories, collects declared outputs,
and guarantees scratch directory cleanup.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import uuid


def sanitize_verilog_header(content: str) -> str:
    """Strip non-deterministic header lines (Date, Host, Command) from Vivado-generated Verilog."""
    lines = content.splitlines(keepends=True)
    out = []
    skip_continuation = False
    for line in lines:
        stripped = line.strip()
        if re.match(r"^//\s*Date\s*:", stripped):
            skip_continuation = False
            continue
        if re.match(r"^//\s*Host\s*:", stripped):
            skip_continuation = False
            continue
        if re.match(r"^//\s*Command\s*:", stripped):
            skip_continuation = True
            continue
        if skip_continuation:
            if stripped.startswith("//") and not re.match(r"^//\s*(-{5,}|[A-Za-z0-9_]+\s*:)", stripped):
                continue
            skip_continuation = False
        out.append(line)
    return "".join(out)


def setup_licensing_and_env(scratch_dir: str, extra_env: list, cmd: list = None) -> dict:
    """Prepare a sanitized environment in scratch_dir preserving licenses."""
    env = dict(os.environ)

    # Inhibit writes to real user configurations
    env["XILINX_LOCAL_USER_DATA"] = "no"

    # Isolate user cache locations to the scratch directory
    env["HOME"] = scratch_dir
    env["APPDATA"] = scratch_dir

    # Infer XILINX_VIVADO from command path if not explicitly provided
    if cmd and "XILINX_VIVADO" not in env:
        cmd_bin = shutil.which(cmd[0]) or cmd[0]
        bin_dir = os.path.dirname(os.path.abspath(cmd_bin))
        parent_dir = os.path.dirname(bin_dir)
        if os.path.basename(bin_dir) == "bin" and os.path.isdir(os.path.join(parent_dir, "data")):
            env["XILINX_VIVADO"] = parent_dir
            current_path = env.get("PATH", "")
            env["PATH"] = f"{bin_dir}:{current_path}:/usr/local/bin:/usr/bin:/bin"

    # Search user's real .Xilinx directory for license files
    potential_xilinx_dirs = []
    real_home = os.path.expanduser("~")
    potential_xilinx_dirs.append(os.path.join(real_home, ".Xilinx"))
    user_name = os.environ.get("USER") or os.environ.get("LOGNAME")
    if user_name and user_name != "root":
        potential_xilinx_dirs.append(f"/home/{user_name}/.Xilinx")

    scratch_xilinx = os.path.join(scratch_dir, ".Xilinx")
    lic_files = []

    for xdir in potential_xilinx_dirs:
        if os.path.isdir(xdir):
            os.makedirs(scratch_xilinx, exist_ok=True)
            try:
                for item in os.listdir(xdir):
                    if item.endswith(".lic"):
                        src = os.path.join(xdir, item)
                        dst = os.path.join(scratch_xilinx, item)
                        if not os.path.exists(dst):
                            os.symlink(src, dst)
                        if dst not in lic_files:
                            lic_files.append(dst)
            except OSError:
                pass

    if "XILINXD_LICENSE_FILE" not in env and lic_files:
        env["XILINXD_LICENSE_FILE"] = ":".join(lic_files)

    # Apply any extra user-specified environment variables
    for item in extra_env or []:
        if "=" in item:
            k, v = item.split("=", 1)
            env[k] = v

    return env


def symlink_execroot_inputs(execroot: str, scratch_dir: str):
    """Symlink entries from execroot into scratch_dir so relative input paths resolve."""
    try:
        for item in os.listdir(execroot):
            if item.startswith("_scratch_") or item.startswith("."):
                continue
            src = os.path.join(execroot, item)
            dst = os.path.join(scratch_dir, item)
            if not os.path.exists(dst):
                try:
                    os.symlink(src, dst)
                except OSError:
                    pass
    except OSError:
        pass


def parse_args():
    parser = argparse.ArgumentParser(
        description="Execute a tool in an isolated scratch directory inside the execroot."
    )
    parser.add_argument(
        "--action-name",
        default="action",
        help="Action identifier used in scratch directory name.",
    )
    parser.add_argument(
        "--copy-input-dir",
        action="append",
        default=[],
        help="Copy an input directory into scratch space as a writable copy (format: src:scratch_rel_dest).",
    )
    parser.add_argument(
        "--copy-input",
        action="append",
        default=[],
        help="Copy an input file into scratch space as a writable copy (format: src:scratch_rel_dest or src).",
    )
    parser.add_argument(
        "--copy-output",
        action="append",
        default=[],
        help="Map of scratch-relative source to destination output file (format: src:dest).",
    )
    parser.add_argument(
        "--sanitize-verilog-output",
        action="append",
        default=[],
        help="Map of scratch-relative source to destination file with header timestamps/hostnames sanitized (format: src:dest).",
    )
    parser.add_argument(
        "--copy-dir-output",
        action="append",
        default=[],
        help="Map of scratch-relative source directory to destination directory (format: src_dir:dest_dir).",
    )
    parser.add_argument(
        "--log-file",
        default=None,
        help="Path where combined stdout and stderr should be written.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Stream stdout/stderr in real time rather than suppressing output on success.",
    )
    parser.add_argument(
        "--env",
        action="append",
        default=[],
        help="Environment variables to set (format: KEY=VALUE).",
    )
    parser.add_argument(
        "--preserve-scratch",
        action="store_true",
        help="Do not remove scratch directory on failure (for debugging).",
    )
    parser.add_argument(
        "command",
        nargs=argparse.REMAINDER,
        help="The command and arguments to execute (preceded by --).",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    cmd = args.command
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        sys.stderr.write("Error: No command provided to run_isolated.py.\n")
        sys.exit(1)

    execroot = os.getcwd()
    scratch_name = f"_scratch_{args.action_name}_{uuid.uuid4().hex[:8]}"
    scratch_dir = os.path.join(execroot, scratch_name)
    os.makedirs(scratch_dir, exist_ok=True)
    symlink_execroot_inputs(execroot, scratch_dir)

    # Make writable copies of declared input directories (e.g. xsim.dir)
    for mapping in args.copy_input_dir:
        if ":" in mapping:
            src_path, dst_rel = mapping.split(":", 1)
            src_full = os.path.abspath(src_path)
            dst_full = os.path.join(scratch_dir, dst_rel)
            if os.path.exists(src_full):
                if os.path.exists(dst_full):
                    shutil.rmtree(dst_full)
                shutil.copytree(src_full, dst_full)
                try:
                    os.chmod(dst_full, 0o755)
                except OSError:
                    pass
                for root, dirs, files in os.walk(dst_full):
                    for d in dirs:
                        try:
                            os.chmod(os.path.join(root, d), 0o755)
                        except OSError:
                            pass
                    for f in files:
                        try:
                            f_path = os.path.join(root, f)
                            st = os.stat(f_path)
                            if st.st_mode & 0o111:
                                os.chmod(f_path, st.st_mode | 0o755)
                            else:
                                os.chmod(f_path, st.st_mode | 0o644)
                        except OSError:
                            pass

    # Make writable copies of declared input files (e.g. .coe, .prj)
    for mapping in args.copy_input:
        if ":" in mapping:
            src_path, dst_rel = mapping.split(":", 1)
        else:
            src_path, dst_rel = mapping, os.path.basename(mapping)
        src_full = os.path.abspath(src_path)
        dst_full = os.path.join(scratch_dir, dst_rel)
        if os.path.exists(src_full):
            try:
                if os.path.exists(dst_full) and os.path.samefile(src_full, dst_full):
                    continue
            except OSError:
                pass
            if os.path.islink(dst_full) or os.path.isfile(dst_full):
                try:
                    os.unlink(dst_full)
                except OSError:
                    pass
            os.makedirs(os.path.dirname(dst_full), exist_ok=True)
            shutil.copy2(src_full, dst_full)
            try:
                os.chmod(dst_full, 0o644)
            except OSError:
                pass

    child_env = setup_licensing_and_env(scratch_dir, args.env, cmd)

    scratch_log_path = os.path.join(scratch_dir, "_run_isolated.log")
    target_log_path = args.log_file or scratch_log_path
    os.makedirs(os.path.dirname(os.path.abspath(target_log_path)), exist_ok=True)

    exit_code = 0
    log_flushed = False

    try:
        with open(target_log_path, "w", encoding="utf-8") as log_fp:
            process = subprocess.Popen(
                cmd,
                cwd=scratch_dir,
                env=child_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )

            for line in process.stdout:
                if args.verbose:
                    sys.stdout.write(line)
                    sys.stdout.flush()
                log_fp.write(line)
                log_fp.flush()

            process.wait()
            exit_code = process.returncode

        if exit_code != 0 and not args.verbose:
            with open(target_log_path, "r", encoding="utf-8", errors="replace") as f:
                shutil.copyfileobj(f, sys.stderr)
            sys.stderr.flush()
            log_flushed = True

        # If successful, extract declared outputs
        if exit_code == 0:
            for mapping in args.copy_output:
                if ":" not in mapping:
                    continue
                src_rel, dst_abs = mapping.split(":", 1)
                src_full = os.path.join(scratch_dir, src_rel)
                dst_full = os.path.abspath(dst_abs)
                if not os.path.exists(src_full):
                    if not args.verbose and not log_flushed:
                        with open(target_log_path, "r", encoding="utf-8", errors="replace") as f:
                            shutil.copyfileobj(f, sys.stderr)
                        sys.stderr.flush()
                        log_flushed = True
                    sys.stderr.write(
                        f"ERROR: Expected declared output '{src_rel}' was not generated in scratch directory.\n"
                    )
                    exit_code = 1
                    break
                os.makedirs(os.path.dirname(dst_full), exist_ok=True)
                shutil.copy2(src_full, dst_full)

            if exit_code == 0:
                for mapping in args.sanitize_verilog_output:
                    if ":" not in mapping:
                        continue
                    src_rel, dst_abs = mapping.split(":", 1)
                    src_full = os.path.join(scratch_dir, src_rel)
                    dst_full = os.path.abspath(dst_abs)
                    if not os.path.exists(src_full):
                        if not args.verbose and not log_flushed:
                            with open(target_log_path, "r", encoding="utf-8", errors="replace") as f:
                                shutil.copyfileobj(f, sys.stderr)
                            sys.stderr.flush()
                            log_flushed = True
                        sys.stderr.write(
                            f"ERROR: Expected declared output '{src_rel}' was not generated in scratch directory.\n"
                        )
                        exit_code = 1
                        break
                    os.makedirs(os.path.dirname(dst_full), exist_ok=True)
                    with open(src_full, "r", encoding="utf-8", errors="replace") as f_in:
                        raw_content = f_in.read()
                    sanitized = sanitize_verilog_header(raw_content)
                    with open(dst_full, "w", encoding="utf-8") as f_out:
                        f_out.write(sanitized)

            for dir_mapping in args.copy_dir_output:
                if ":" not in dir_mapping:
                    continue
                src_rel, dst_abs = dir_mapping.split(":", 1)
                src_full = os.path.join(scratch_dir, src_rel)
                dst_full = os.path.abspath(dst_abs)
                if not os.path.exists(src_full):
                    if not args.verbose and not log_flushed:
                        with open(target_log_path, "r", encoding="utf-8", errors="replace") as f:
                            shutil.copyfileobj(f, sys.stderr)
                        sys.stderr.flush()
                        log_flushed = True
                    sys.stderr.write(
                        f"ERROR: Expected declared directory output '{src_rel}' was not generated.\n"
                    )
                    exit_code = 1
                    break
                if os.path.exists(dst_full):
                    shutil.rmtree(dst_full)
                shutil.copytree(src_full, dst_full)

    finally:
        # Clean up scratch directory unconditionally unless debugging
        if exit_code != 0 and args.preserve_scratch:
            sys.stderr.write(
                f"Preserving scratch directory for debug inspection: {scratch_dir}\n"
            )
        else:
            shutil.rmtree(scratch_dir, ignore_errors=True)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
