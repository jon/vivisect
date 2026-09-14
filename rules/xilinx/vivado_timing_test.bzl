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

"""Machine-readable FPGA timing closure assertion test rule.

Parses Vivado implementation timing summary reports (impl_timing_summary.rpt)
in a lightweight, sandboxed Python runner and verifies Worst Negative Slack (WNS),
Worst Hold Slack (WHS), and Total Negative Slack (TNS) against strict bounds.
"""

load("//rules:providers.bzl", "VivadoDcpInfo")

_TEST_BODY = '''
def parse_float(s):
    try:
        return float(s)
    except (ValueError, TypeError):
        return None

def parse_int(s):
    try:
        return int(s)
    except (ValueError, TypeError):
        return None

def parse_timing_report(report_path):
    with open(report_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    metrics = {}
    lines = content.splitlines()
    in_summary_table = False
    dashed_line_seen = False

    COLUMNS = [
        "WNS(ns)", "TNS(ns)", "TNS Failing Endpoints", "TNS Total Endpoints",
        "WHS(ns)", "THS(ns)", "THS Failing Endpoints", "THS Total Endpoints",
        "WPWS(ns)", "TPWS(ns)", "TPWS Failing Endpoints", "TPWS Total Endpoints",
    ]

    for line in lines:
        stripped = line.strip()
        if "Design Timing Summary" in stripped:
            in_summary_table = True
            continue
        if in_summary_table:
            if "WNS(ns)" in stripped:
                continue
            if stripped.startswith("-------"):
                dashed_line_seen = True
                continue
            if dashed_line_seen and stripped:
                vals = stripped.split()
                if len(vals) >= 6:
                    for i, v in enumerate(vals[:len(COLUMNS)]):
                        metrics[COLUMNS[i]] = v
                    break
            elif dashed_line_seen and not stripped:
                continue

    return metrics, content

def main():
    report_path = TIMING_REPORT_PATH
    if not os.path.exists(report_path):
        runfiles = os.environ.get("RUNFILES_DIR")
        workspace = os.environ.get("TEST_WORKSPACE", "_main")
        if runfiles:
            cand = os.path.join(runfiles, workspace, report_path)
            if os.path.exists(cand):
                report_path = cand

    if not os.path.exists(report_path):
        sys.stderr.write(f"ERROR: Timing summary report not found at {report_path}\\n")
        sys.exit(1)

    metrics, full_text = parse_timing_report(report_path)

    if not metrics:
        # Check if the design was empty or completely unconstrained
        if "There are no user specified timing constraints" in full_text:
            sys.stderr.write("WARNING: Design contains no user specified timing constraints.\\n")
        else:
            sys.stderr.write(f"ERROR: Failed to parse Design Timing Summary table from {report_path}\\n")
            sys.exit(1)

    wns = parse_float(metrics.get("WNS(ns)"))
    tns = parse_float(metrics.get("TNS(ns)"))
    tns_failing = parse_int(metrics.get("TNS Failing Endpoints", 0))
    whs = parse_float(metrics.get("WHS(ns)") or metrics.get("TWH(ns)"))
    ths = parse_float(metrics.get("THS(ns)"))
    ths_failing = parse_int(metrics.get("THS Failing Endpoints", 0))

    failed = False
    reasons = []

    print("=== Vivado Timing Closure Scorecard ===")
    print(f"{'Metric':<25} | {'Actual Value':<14} | {'Required Bound':<16} | {'Status'}")
    print("-" * 75)

    def check_min(name, actual, min_val):
        nonlocal failed
        if actual is None:
            print(f"{name:<25} | {'N/A':<14} | {'>= ' + str(min_val):<16} | FAIL (Missing)")
            failed = True
            reasons.append(f"{name} missing from report")
            return
        status = "PASS"
        if min_val is not None and actual < min_val:
            status = f"FAIL ({actual:.3f} < {min_val:.3f})"
            failed = True
            reasons.append(f"{name} violated: {actual:.3f}ns < {min_val:.3f}ns")
        print(f"{name:<25} | {actual:<14.3f} | {'>= ' + str(min_val) + ' ns':<16} | {status}")

    def check_max(name, actual, max_val):
        nonlocal failed
        if actual is None:
            print(f"{name:<25} | {'N/A':<14} | {'<= ' + str(max_val):<16} | FAIL (Missing)")
            failed = True
            reasons.append(f"{name} missing from report")
            return
        status = "PASS"
        if max_val is not None and abs(actual) > abs(max_val):
            status = f"FAIL ({actual:.3f} > {max_val:.3f})"
            failed = True
            reasons.append(f"{name} violated: {actual:.3f}ns > {max_val:.3f}ns")
        print(f"{name:<25} | {actual:<14.3f} | {'<= ' + str(max_val) + ' ns':<16} | {status}")

    if MIN_WNS is not None:
        check_min("Worst Negative Slack (WNS)", wns, MIN_WNS)
    if MIN_WHS is not None:
        check_min("Worst Hold Slack (WHS)", whs, MIN_WHS)
    if MAX_TNS is not None:
        check_max("Total Negative Slack (TNS)", tns, MAX_TNS)
    if MAX_THS is not None:
        check_max("Total Hold Slack (THS)", ths, MAX_THS)

    print("-" * 75)

    if failed:
        sys.stderr.write("ERROR: Timing closure constraints violated:\\n")
        for r in reasons:
            sys.stderr.write(f"  * {r}\\n")
        sys.exit(1)
    else:
        print("SUCCESS: All timing closure constraints satisfied.")
        sys.exit(0)

if __name__ == "__main__":
    main()
'''

def _vivado_timing_test_impl(ctx):
    dcp_info = ctx.attr.checkpoint[VivadoDcpInfo]
    if "timing" not in dcp_info.reports:
        fail("Target checkpoint '%s' does not provide a timing summary report ('timing')." % ctx.attr.checkpoint.label)

    timing_file = dcp_info.reports["timing"]

    min_wns = float(ctx.attr.min_wns) if ctx.attr.min_wns else None
    min_whs = float(ctx.attr.min_whs) if ctx.attr.min_whs else None
    max_tns = float(ctx.attr.max_tns) if ctx.attr.max_tns else None
    max_ths = float(ctx.attr.max_ths) if ctx.attr.max_ths else None

    script = ctx.actions.declare_file(ctx.label.name + "_runner.py")
    script_header = """#!/usr/bin/env python3
import os
import re
import sys

TIMING_REPORT_PATH = "%s"
MIN_WNS = %s
MIN_WHS = %s
MAX_TNS = %s
MAX_THS = %s
""" % (
        timing_file.short_path,
        repr(min_wns),
        repr(min_whs),
        repr(max_tns),
        repr(max_ths),
    )

    ctx.actions.write(
        output = script,
        content = script_header + _TEST_BODY,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [timing_file])

    return [
        DefaultInfo(
            executable = script,
            runfiles = runfiles,
        ),
    ]

vivado_timing_test = rule(
    implementation = _vivado_timing_test_impl,
    test = True,
    doc = "Asserts timing closure constraints (WNS, WHS, TNS, THS) against Vivado implementation timing summary reports.",
    attrs = {
        "checkpoint": attr.label(
            mandatory = True,
            providers = [VivadoDcpInfo],
            doc = "Vivado implementation target (vivado_impl) providing VivadoDcpInfo with timing report.",
        ),
        "min_wns": attr.string(
            default = "0.0",
            doc = "Minimum allowed Worst Negative Slack in ns (defaults to '0.0', failing if setup slack is negative). Set empty string for no cap.",
        ),
        "min_whs": attr.string(
            default = "0.0",
            doc = "Minimum allowed Worst Hold Slack in ns (defaults to '0.0', failing if hold slack is negative). Set empty string for no cap.",
        ),
        "max_tns": attr.string(
            default = "0.0",
            doc = "Maximum allowed Total Negative Slack in ns (defaults to '0.0'). Set empty string for no cap.",
        ),
        "max_ths": attr.string(
            default = "0.0",
            doc = "Maximum allowed Total Hold Slack in ns (defaults to '0.0'). Set empty string for no cap.",
        ),
    },
)
