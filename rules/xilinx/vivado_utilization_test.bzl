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

"""Machine-readable FPGA resource utilization assertion test rule."""

load("//rules:providers.bzl", "VivadoDcpInfo")

_TEST_BODY = '''
def parse_val(s):
    try:
        return int(s)
    except (ValueError, TypeError):
        try:
            return float(s)
        except (ValueError, TypeError):
            return 0

def main():
    json_path = JSON_PATH
    if not os.path.exists(json_path):
        runfiles = os.environ.get("RUNFILES_DIR")
        workspace = os.environ.get("TEST_WORKSPACE", "_main")
        if runfiles:
            cand = os.path.join(runfiles, workspace, json_path)
            if os.path.exists(cand):
                json_path = cand

    if not os.path.exists(json_path):
        sys.stderr.write(f"ERROR: Utilization JSON report not found at {json_path}\\n")
        sys.exit(1)

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    tables = data.get("tables", {})
    partname = data.get("report_header", {}).get("partname", "unknown")
    designname = data.get("report_header", {}).get("designname", "unknown")

    metrics = {}

    def ingest_table(table_name, target_rows):
        tbl = tables.get(table_name, {})
        headers = tbl.get("headers", [])
        if "Site Type" not in headers or "Used" not in headers:
            return
        idx_type = headers.index("Site Type")
        idx_used = headers.index("Used")
        idx_avail = headers.index("Available") if "Available" in headers else -1

        for row in tbl.get("data", []):
            st = row[idx_type]
            if ":" in st:
                continue
            clean_st = st.rstrip("*")
            for key, pattern in target_rows.items():
                if clean_st == pattern:
                    used = parse_val(row[idx_used])
                    avail = parse_val(row[idx_avail]) if idx_avail >= 0 else 0
                    metrics[key] = {"used": used, "available": avail}

    ingest_table("Slice Logic", {
        "luts": "Slice LUTs",
        "registers": "Slice Registers",
        "f7_muxes": "F7 Muxes",
        "f8_muxes": "F8 Muxes",
        "slice": "Slice",
    })
    ingest_table("Memory", {
        "bram": "Block RAM Tile",
    })
    ingest_table("DSP", {
        "dsps": "DSPs",
    })

    failed = False
    print(f"=== Vivado Utilization Report: {designname} (Part: {partname}) ===")
    print(f"{'Resource':<18} | {'Used':<8} | {'Available':<10} | {'Max Cap':<8} | {'Actual %':<8} | {'Max %':<8} | {'Status'}")
    print("-" * 80)

    for res, info in metrics.items():
        used = info["used"]
        avail = info["available"]
        act_pct = (float(used) / float(avail) * 100.0) if avail > 0 else 0.0

        max_cap = CAPS.get(res, -1)
        max_pct = PCT_CAPS.get(res, -1.0)

        res_ok = True
        status_reasons = []

        if max_cap >= 0 and used > max_cap:
            res_ok = False
            status_reasons.append(f"Exceeded count {used} > {max_cap}")

        if max_pct >= 0.0 and act_pct > max_pct:
            res_ok = False
            status_reasons.append(f"Exceeded percentage {act_pct:.2f}% > {max_pct:.2f}%")

        if not res_ok:
            failed = True

        status_str = "PASS" if res_ok else "FAIL (" + "; ".join(status_reasons) + ")"
        cap_str = str(max_cap) if max_cap >= 0 else "-"
        pct_cap_str = f"{max_pct:.1f}%" if max_pct >= 0.0 else "-"
        act_pct_str = f"{act_pct:.2f}%"

        print(f"{res:<18} | {used:<8} | {avail:<10} | {cap_str:<8} | {act_pct_str:<8} | {pct_cap_str:<8} | {status_str}")

    for res, max_cap in CAPS.items():
        if max_cap >= 0 and res not in metrics:
            print(f"{res:<18} | {'N/A':<8} | {'N/A':<10} | {max_cap:<8} | {'-':<8} | {'-':<8} | {'PASS (0 used)'}")

    print("-" * 80)
    if failed:
        sys.stderr.write("ERROR: FPGA utilization limits violated.\\n")
        sys.exit(1)
    else:
        print("All utilization constraints satisfied.")
        sys.exit(0)

if __name__ == "__main__":
    main()
'''

def _vivado_utilization_test_impl(ctx):
    dcp_info = ctx.attr.checkpoint[VivadoDcpInfo]
    if "utilization_json" not in dcp_info.reports:
        fail("Target checkpoint '%s' does not provide an 'utilization_json' report." % ctx.attr.checkpoint.label)

    json_file = dcp_info.reports["utilization_json"]

    caps = {
        "luts": ctx.attr.max_luts,
        "registers": ctx.attr.max_registers,
        "bram": ctx.attr.max_bram,
        "dsps": ctx.attr.max_dsps,
        "slice": ctx.attr.max_slices,
    }

    pct_caps = {
        "luts": float(ctx.attr.max_lut_pct) if ctx.attr.max_lut_pct else -1.0,
        "registers": float(ctx.attr.max_register_pct) if ctx.attr.max_register_pct else -1.0,
        "bram": float(ctx.attr.max_bram_pct) if ctx.attr.max_bram_pct else -1.0,
        "dsps": float(ctx.attr.max_dsp_pct) if ctx.attr.max_dsp_pct else -1.0,
        "slice": float(ctx.attr.max_slice_pct) if ctx.attr.max_slice_pct else -1.0,
    }

    script = ctx.actions.declare_file(ctx.label.name + "_runner.py")
    script_header = """#!/usr/bin/env python3
import json
import os
import sys

JSON_PATH = "%s"
CAPS = %s
PCT_CAPS = %s
""" % (json_file.short_path, repr(caps), repr(pct_caps))

    ctx.actions.write(
        output = script,
        content = script_header + _TEST_BODY,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [json_file])

    return [
        DefaultInfo(
            executable = script,
            runfiles = runfiles,
        ),
    ]

vivado_utilization_test = rule(
    implementation = _vivado_utilization_test_impl,
    test = True,
    doc = "Asserts absolute and proportional resource utilization caps against Vivado synthesis or implementation reports.",
    attrs = {
        "checkpoint": attr.label(
            mandatory = True,
            providers = [VivadoDcpInfo],
            doc = "Vivado synthesis or implementation target providing VivadoDcpInfo.",
        ),
        "max_luts": attr.int(
            default = -1,
            doc = "Maximum allowed LUT count (-1 for no cap).",
        ),
        "max_registers": attr.int(
            default = -1,
            doc = "Maximum allowed Slice Register count (-1 for no cap).",
        ),
        "max_bram": attr.int(
            default = -1,
            doc = "Maximum allowed Block RAM Tile count (-1 for no cap).",
        ),
        "max_dsps": attr.int(
            default = -1,
            doc = "Maximum allowed DSP count (-1 for no cap).",
        ),
        "max_slices": attr.int(
            default = -1,
            doc = "Maximum allowed Slice count (-1 for no cap).",
        ),
        "max_lut_pct": attr.string(
            default = "",
            doc = "Maximum allowed LUT utilization percentage (e.g. '50.0').",
        ),
        "max_register_pct": attr.string(
            default = "",
            doc = "Maximum allowed Slice Register utilization percentage.",
        ),
        "max_bram_pct": attr.string(
            default = "",
            doc = "Maximum allowed Block RAM utilization percentage.",
        ),
        "max_dsp_pct": attr.string(
            default = "",
            doc = "Maximum allowed DSP utilization percentage.",
        ),
        "max_slice_pct": attr.string(
            default = "",
            doc = "Maximum allowed Slice utilization percentage.",
        ),
    },
)
