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

"""Unit tests for vivado_utilization_test parsing and assertion logic."""

import json
import subprocess
import sys
import tempfile
import unittest

SAMPLE_JSON = {
    "report_header": {
        "cmdline": "report_utilization -json test.json",
        "designname": "test_core",
        "partname": "xc7a100tcsg324-1",
    },
    "tables": {
        "Slice Logic": {
            "headers": ["Site Type", "Used", "Fixed", "Prohibited", "Available", "Util%"],
            "data": [
                ["Slice LUTs*", "150", "0", "0", "63400", "0.24"],
                ["Slice LUTs*:LUT as Logic", "150", "0", "0", "63400", "0.24"],
                ["Slice Registers", "200", "0", "0", "126800", "0.16"],
                ["Slice Registers:Register as Flip Flop", "200", "0", "0", "126800", "0.16"],
            ],
        },
        "Memory": {
            "headers": ["Site Type", "Used", "Fixed", "Prohibited", "Available", "Util%"],
            "data": [
                ["Block RAM Tile", "5", "0", "0", "135", "3.70"],
            ],
        },
        "DSP": {
            "headers": ["Site Type", "Used", "Fixed", "Prohibited", "Available", "Util%"],
            "data": [
                ["DSPs", "2", "0", "0", "240", "0.83"],
            ],
        },
    },
}

class UtilizationTest(unittest.TestCase):
    def run_check(self, json_data, caps, pct_caps):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(json_data, f)
            f.flush()
            json_file = f.name

        code = f"""
import json, os, sys
JSON_PATH = "{json_file}"
CAPS = {caps}
PCT_CAPS = {pct_caps}

def parse_val(s):
    try: return int(s)
    except:
        try: return float(s)
        except: return 0

with open(JSON_PATH, "r") as f:
    data = json.load(f)

tables = data.get("tables", {{}})
metrics = {{}}

def ingest_table(table_name, target_rows):
    tbl = tables.get(table_name, {{}})
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
                metrics[key] = {{"used": used, "available": avail}}

ingest_table("Slice Logic", {{"luts": "Slice LUTs", "registers": "Slice Registers"}})
ingest_table("Memory", {{"bram": "Block RAM Tile"}})
ingest_table("DSP", {{"dsps": "DSPs"}})

failed = False
for res, info in metrics.items():
    used = info["used"]
    avail = info["available"]
    act_pct = (float(used) / float(avail) * 100.0) if avail > 0 else 0.0
    max_cap = CAPS.get(res, -1)
    max_pct = PCT_CAPS.get(res, -1.0)
    if max_cap >= 0 and used > max_cap:
        failed = True
    if max_pct >= 0.0 and act_pct > max_pct:
        failed = True

if failed:
    sys.exit(1)
sys.exit(0)
"""
        proc = subprocess.run([sys.executable, "-c", code], capture_output=True)
        return proc.returncode

    def test_passing_caps(self):
        rc = self.run_check(SAMPLE_JSON, {"luts": 200, "registers": 300}, {"luts": 1.0, "registers": 1.0})
        self.assertEqual(rc, 0)

    def test_exceeded_lut_count(self):
        rc = self.run_check(SAMPLE_JSON, {"luts": 100}, {})
        self.assertEqual(rc, 1)

    def test_exceeded_reg_percentage(self):
        rc = self.run_check(SAMPLE_JSON, {}, {"registers": 0.1})
        self.assertEqual(rc, 1)

if __name__ == "__main__":
    unittest.main()
