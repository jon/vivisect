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

"""Hardware-in-the-loop (HIL) test harness for FPGA designs.

Orchestrates automated testing against physical FPGA hardware:
1. Acquires physical device lock (TargetLock) to ensure mutual exclusion.
2. Programs target FPGA with specified bitstream via Vivado Hardware Manager.
3. Executes hardware test assertions:
   - Built-in UART assertion runner (verifying expected output patterns).
   - Vivado Hardware Manager Tcl script (inspecting VIO/ILA probes).
   - Custom test runner binary or script.
4. Produces clear diagnostics and test scorecards adhering to Bazel test standards.
"""

import argparse
import os
import subprocess
import sys
import time

# Add containing directory to import path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hw_client import UartClient, detect_uart_port
import hw_program_runner
from target_lock import TargetLock


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Execute hardware-in-the-loop test against physical FPGA."
    )
    # Programming options
    parser.add_argument("--bitstream", required=True, help="Path to bitstream (.bit) file.")
    parser.add_argument("--probes", default=None, help="Optional debug probes (.ltx) file.")
    parser.add_argument("--part", default="", help="Expected FPGA part string.")
    parser.add_argument("--device", default="", help="Target hw_device name or pattern.")
    parser.add_argument("--target", default="", help="Target hw_target name or cable serial.")
    parser.add_argument("--url", default="localhost:3121", help="hw_server URL.")
    parser.add_argument("--vivado-bin", default="/tools/Xilinx/2026.1/Vivado/bin/vivado", help="Path to vivado.")
    parser.add_argument("--isolated-runner", default="", help="Path to run_isolated.py.")
    parser.add_argument("--lock-timeout", type=float, default=60.0, help="Device lock timeout in seconds.")
    parser.add_argument("--skip-program", action="store_true", help="Skip programming phase.")
    parser.add_argument("--mock", action="store_true", help="Simulate test in mock mode without hardware.")

    # Test mode options
    parser.add_argument(
        "--mode",
        choices=["uart", "tcl", "runner", "done_only"],
        default="done_only",
        help="Test verification mode.",
    )

    # UART mode options
    parser.add_argument("--uart-port", default="auto", help="Serial port path or 'auto'.")
    parser.add_argument("--uart-baud", type=int, default=115200, help="UART baud rate.")
    parser.add_argument("--uart-timeout", type=float, default=15.0, help="UART assertion timeout.")
    parser.add_argument(
        "--uart-expect",
        action="append",
        default=[],
        help="Expected string or regex pattern (may be specified multiple times).",
    )
    parser.add_argument("--uart-send", default="", help="Optional data string to transmit upon opening UART.")

    # Tcl mode options
    parser.add_argument("--tcl-test", default=None, help="Path to Tcl test script.")

    # Custom runner options
    parser.add_argument("--test-runner", default=None, help="Path to custom test executable.")
    parser.add_argument(
        "runner_args",
        nargs=argparse.REMAINDER,
        help="Extra arguments passed to custom test runner.",
    )

    return parser.parse_args(argv)


def run_uart_test(args, is_mock: bool = False, client: UartClient = None) -> int:
    """Execute serial assertion test."""
    print("--- [Phase 2: UART Assertion Test] ---")
    if is_mock:
        print(f"[MOCK] Opening simulated UART port '{args.uart_port}' at {args.uart_baud} baud.")
        if args.uart_send:
            print(f"[MOCK] Transmitted payload: {repr(args.uart_send)}")
        for pat in args.uart_expect:
            print(f"[MOCK] Matched expected pattern: '{pat}'")
        print("SUCCESS: [MOCK] All UART assertion patterns verified.")
        return 0

    resolved_port = detect_uart_port(args.uart_port)
    print(f"Listening on UART port: {resolved_port} ({args.uart_baud} baud)")

    own_client = False
    if client is None:
        client = UartClient(port=resolved_port, baudrate=args.uart_baud, timeout=args.uart_timeout)
        client.open()
        own_client = True

    try:
        if args.uart_send:
            print(f"Transmitting stimulus: {repr(args.uart_send)}")
            client.send(args.uart_send)

        for pat in args.uart_expect:
            print(f"Waiting for pattern: '{pat}' (timeout: {args.uart_timeout}s)...")
            buf = client.expect(pat, timeout=args.uart_timeout)
            print(f"  -> Matched pattern '{pat}' in stream.")

        # Display any trailing remainder
        time.sleep(0.1)
        tail = client.read_all()
        if tail:
            print(f"Trailing serial output: {repr(tail)}")

        print("SUCCESS: All UART assertion patterns satisfied.")
        return 0
    except Exception as err:
        sys.stderr.write(f"\nERROR: UART assertion failed: {err}\n")
        return 1
    finally:
        if own_client:
            client.close()



def run_tcl_test(args, is_mock: bool = False) -> int:
    """Execute Vivado Tcl hardware test script."""
    print("--- [Phase 2: Vivado Tcl Hardware Test] ---")
    if is_mock:
        print(f"[MOCK] Simulating Tcl hardware test script: {args.tcl_test}")
        print("SUCCESS: [MOCK] Tcl hardware test script passed.")
        return 0

    if not args.tcl_test or not os.path.exists(args.tcl_test):
        sys.stderr.write(f"ERROR: Tcl test script not found: {args.tcl_test}\n")
        return 1

    cmd = []
    if args.isolated_runner and os.path.exists(args.isolated_runner):
        cmd.extend([
            sys.executable,
            args.isolated_runner,
            "--action-name", "hw_tcl_test",
            "--verbose",
            "--",
        ])

    cmd.extend([
        args.vivado_bin,
        "-mode", "batch",
        "-nojournal",
        "-nolog",
        "-source", os.path.abspath(args.tcl_test),
    ])

    res = subprocess.run(cmd, text=True)
    if res.returncode != 0:
        sys.stderr.write(f"ERROR: Tcl hardware test failed with exit code {res.returncode}.\n")
        return res.returncode

    print("SUCCESS: Tcl hardware test completed cleanly.")
    return 0


def run_custom_runner(args, is_mock: bool = False) -> int:
    """Execute custom user test runner."""
    print("--- [Phase 2: Custom Test Runner] ---")
    if is_mock:
        print(f"[MOCK] Simulating custom runner: {args.test_runner}")
        print("SUCCESS: [MOCK] Custom runner passed.")
        return 0

    if not args.test_runner or not os.path.exists(args.test_runner):
        sys.stderr.write(f"ERROR: Test runner not found: {args.test_runner}\n")
        return 1

    child_env = dict(os.environ)
    child_env["VIVISECT_BITSTREAM"] = os.path.abspath(args.bitstream)
    child_env["VIVISECT_UART_PORT"] = detect_uart_port(args.uart_port)
    child_env["VIVISECT_HW_DEVICE"] = args.device
    child_env["VIVISECT_HW_TARGET"] = args.target
    child_env["VIVISECT_HW_SERVER"] = args.url

    cmd = [args.test_runner] + (args.runner_args or [])
    res = subprocess.run(cmd, env=child_env, text=True)
    if res.returncode != 0:
        sys.stderr.write(f"ERROR: Custom test runner exited with code {res.returncode}.\n")
        return res.returncode

    print("SUCCESS: Custom test runner completed cleanly.")
    return 0


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)
    args = parse_args(argv)

    is_mock = args.mock or os.environ.get("VIVISECT_MOCK_HARDWARE") == "1"
    target_lock_id = args.target or args.device or args.part or "default_fpga"

    print("================================================================")
    print(" Vivisect Hardware-in-the-Loop Test Harness")
    print(f" Bitstream:     {args.bitstream}")
    print(f" Test Mode:     {args.mode}")
    print(f" Target Lock:   {target_lock_id}")
    if is_mock:
        print(" Execution:     MOCK (Simulated Hardware)")
    print("================================================================")

    # Automatically select mode if not explicitly set
    mode = args.mode
    if mode == "done_only":
        if args.uart_expect:
            mode = "uart"
        elif args.tcl_test:
            mode = "tcl"
        elif args.test_runner:
            mode = "runner"

    with TargetLock(target_lock_id, timeout=args.lock_timeout):
        uart_client = None
        if mode == "uart" and not is_mock:
            resolved_port = detect_uart_port(args.uart_port)
            print(f"Opening serial port {resolved_port} prior to FPGA programming...")
            uart_client = UartClient(
                port=resolved_port,
                baudrate=args.uart_baud,
                timeout=args.uart_timeout,
            )
            try:
                uart_client.open()
            except Exception as err:
                print(f"Warning: Could not pre-open UART: {err}")
                uart_client = None

        try:
            # Phase 1: Program the FPGA
            if not args.skip_program:
                print("--- [Phase 1: FPGA Configuration] ---")
                prog_argv = [
                    "--bitstream", args.bitstream,
                    "--url", args.url,
                    "--lock-timeout", str(args.lock_timeout),
                ]
                if args.probes:
                    prog_argv.extend(["--probes", args.probes])
                if args.part:
                    prog_argv.extend(["--part", args.part])
                if args.device:
                    prog_argv.extend(["--device", args.device])
                if args.target:
                    prog_argv.extend(["--target", args.target])
                if args.vivado_bin:
                    prog_argv.extend(["--vivado-bin", args.vivado_bin])
                if args.isolated_runner:
                    prog_argv.extend(["--isolated-runner", args.isolated_runner])
                if is_mock:
                    prog_argv.append("--mock")

                rc = hw_program_runner.main(prog_argv)
                if rc != 0:
                    sys.stderr.write("ERROR: Programming phase failed. Aborting HIL test.\n")
                    return rc
            else:
                print("INFO: Skipping FPGA programming phase (--skip-program specified).")

            # Phase 2: Execute Test Assertions
            if mode == "uart":
                rc = run_uart_test(args, is_mock=is_mock, client=uart_client)
            elif mode == "tcl":
                rc = run_tcl_test(args, is_mock=is_mock)
            elif mode == "runner":
                rc = run_custom_runner(args, is_mock=is_mock)
            else:
                # done_only mode: programming verification was sufficient
                print("SUCCESS: FPGA configuration verified (DONE pin = 1).")
                rc = 0
        finally:
            if uart_client:
                uart_client.close()


        if rc != 0:
            sys.stderr.write("================================================================\n")
            sys.stderr.write(" Vivisect HIL Test: FAILED\n")
            sys.stderr.write("================================================================\n")
            return rc

    print("================================================================")
    print(" Vivisect HIL Test: ALL ASSERTIONS PASSED")
    print("================================================================")
    return 0


if __name__ == "__main__":
    sys.exit(main())
