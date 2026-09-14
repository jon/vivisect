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

"""Unit tests for vivado_timing_test parsing and assertion logic."""

import subprocess
import sys
import tempfile
import unittest

SAMPLE_TIMING_REPORT = """
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2026.1 (lin64)
| Design       : top_system
| Device       : 7a100t-csg324
| Design State : Routed
------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------
| Design Timing Summary
| ---------------------
------------------------------------------------------------------------------------------------

    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints
    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------
      5.120        0.000                      0                   16        0.245        0.000                      0                   16        4.500        0.000                       0                    16

All user specified timing constraints are met.
"""

SAMPLE_FAILING_TIMING_REPORT = """
------------------------------------------------------------------------------------------------
| Design Timing Summary
| ---------------------
------------------------------------------------------------------------------------------------

    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints
    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------
     -1.240       -8.450                      5                   16       -0.050       -0.120                      2                   16        4.500        0.000                       0                    16

Timing constraints are not met.
"""

class TimingTest(unittest.TestCase):
    def run_check(self, report_text, min_wns=0.0, min_whs=0.0, max_tns=0.0):
        with tempfile.NamedTemporaryFile("w", suffix=".rpt", delete=False) as f:
            f.write(report_text)
            f.flush()
            rpt_file = f.name

        code = f"""
import os, sys

TIMING_REPORT_PATH = "{rpt_file}"
MIN_WNS = {min_wns}
MIN_WHS = {min_whs}
MAX_TNS = {max_tns}
MAX_THS = 0.0

def parse_float(s):
    try: return float(s)
    except: return None

def parse_int(s):
    try: return int(s)
    except: return None

def parse_timing_report(report_path):
    with open(report_path, "r") as f: content = f.read()
    metrics = {{}}
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
            if "WNS(ns)" in stripped: continue
            if stripped.startswith("-------"):
                dashed_line_seen = True
                continue
            if dashed_line_seen and stripped:
                vals = stripped.split()
                if len(vals) >= 6:
                    for i, v in enumerate(vals[:len(COLUMNS)]):
                        metrics[COLUMNS[i]] = v
                    break
    return metrics

metrics = parse_timing_report(TIMING_REPORT_PATH)
wns = parse_float(metrics.get("WNS(ns)"))
tns = parse_float(metrics.get("TNS(ns)"))
whs = parse_float(metrics.get("WHS(ns)"))

failed = False
if MIN_WNS is not None and (wns is None or wns < MIN_WNS): failed = True
if MIN_WHS is not None and (whs is None or whs < MIN_WHS): failed = True
if MAX_TNS is not None and (tns is None or abs(tns) > abs(MAX_TNS)): failed = True

sys.exit(1 if failed else 0)
"""
        proc = subprocess.run([sys.executable, "-c", code], capture_output=True)
        return proc.returncode

    def test_passing_timing(self):
        rc = self.run_check(SAMPLE_TIMING_REPORT, min_wns=0.0, min_whs=0.0, max_tns=0.0)
        self.assertEqual(rc, 0)

    def test_strict_passing_wns(self):
        rc = self.run_check(SAMPLE_TIMING_REPORT, min_wns=5.0)
        self.assertEqual(rc, 0)

    def test_exceeded_wns_threshold(self):
        rc = self.run_check(SAMPLE_TIMING_REPORT, min_wns=6.0)
        self.assertEqual(rc, 1)

    def test_failing_timing_report(self):
        rc = self.run_check(SAMPLE_FAILING_TIMING_REPORT, min_wns=0.0, min_whs=0.0, max_tns=0.0)
        self.assertEqual(rc, 1)

if __name__ == "__main__":
    unittest.main()
