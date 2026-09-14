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

"""Integration test verifying that Vivisect rules reliably trap negative cases.

Validates:
1. Syntax and lint violations in Verilator fail with diagnostic errors.
2. SV assertion / $fatal errors in XSim fail with trapped simulation errors.
3. SV assertion / $fatal errors in Verilator fail with trapped simulation errors.
"""

import os
import subprocess
import unittest

class NegativeTrappingTest(unittest.TestCase):

    def _resolve_binary(self, bin_name):
        runfiles_dir = os.environ.get("PYTHON_RUNFILES") or os.environ.get("TEST_SRCDIR")
        candidates = [bin_name, bin_name + ".sh"]
        if runfiles_dir:
            for repo in ["_main", "vivisect"]:
                for c in candidates:
                    path = os.path.join(runfiles_dir, repo, "rules", "xilinx", "test", "negative", c)
                    if os.path.exists(path):
                        return path
        for c in candidates:
            local_path = os.path.join("rules", "xilinx", "test", "negative", c)
            if os.path.exists(local_path):
                return os.path.abspath(local_path)
        raise FileNotFoundError(f"Cannot find binary {bin_name}")

    def test_lint_failure_trapped(self):
        bin_path = self._resolve_binary("failing_lint_test")
        proc = subprocess.run(
            [bin_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        self.assertNotEqual(proc.returncode, 0, f"Expected non-zero exit, got {proc.returncode}")
        self.assertTrue(
            "%Error" in proc.stdout or "syntax error" in proc.stdout,
            f"Expected syntax error diagnostic in output:\n{proc.stdout}",
        )

    def test_xsim_assertion_failure_trapped(self):
        bin_path = self._resolve_binary("failing_assertion_xsim")
        proc = subprocess.run(
            [bin_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        self.assertNotEqual(proc.returncode, 0, f"Expected non-zero exit, got {proc.returncode}")
        self.assertTrue(
            "SIMULATION FAILED" in proc.stdout or "$fatal" in proc.stdout or "assertion failure" in proc.stdout,
            f"Expected failure diagnostic in XSim output:\n{proc.stdout}",
        )

    def test_verilator_assertion_failure_trapped(self):
        bin_path = self._resolve_binary("failing_assertion_verilator")
        proc = subprocess.run(
            [bin_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        self.assertNotEqual(proc.returncode, 0, f"Expected non-zero exit, got {proc.returncode}")
        self.assertTrue(
            "assertion failure" in proc.stdout or "%Error" in proc.stdout or "Fatal" in proc.stdout,
            f"Expected failure diagnostic in Verilator output:\n{proc.stdout}",
        )

if __name__ == "__main__":
    unittest.main()
