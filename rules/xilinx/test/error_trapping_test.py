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

import os
import subprocess
import unittest

class XsimErrorTrappingTest(unittest.TestCase):

    def _resolve_binary(self, bin_name):
        runfiles_dir = os.environ.get("PYTHON_RUNFILES") or os.environ.get("TEST_SRCDIR")
        candidates = [bin_name, bin_name + ".sh"]
        if runfiles_dir:
            for repo in ["_main", "vivisect"]:
                for c in candidates:
                    path = os.path.join(runfiles_dir, repo, "rules", "xilinx", "test", c)
                    if os.path.exists(path):
                        return path
        for c in candidates:
            local_path = os.path.join("rules", "xilinx", "test", c)
            if os.path.exists(local_path):
                return os.path.abspath(local_path)
        raise FileNotFoundError(f"Cannot find binary {bin_name}")

    def test_fatal_trapping(self):
        bin_path = self._resolve_binary("fatal_xsim_test")
        proc = subprocess.run(
            [bin_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        print("Fatal test output:\n", proc.stdout)
        self.assertEqual(proc.returncode, 1, f"Expected exit code 1, got {proc.returncode}")
        self.assertIn("SIMULATION FAILED", proc.stdout)
        self.assertIn("SystemVerilog $fatal condition detected", proc.stdout)

    def test_error_trapping(self):
        bin_path = self._resolve_binary("error_failing_xsim_test")
        proc = subprocess.run(
            [bin_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        print("Error test output:\n", proc.stdout)
        self.assertEqual(proc.returncode, 1, f"Expected exit code 1, got {proc.returncode}")
        self.assertIn("SIMULATION FAILED", proc.stdout)
        self.assertIn("SystemVerilog $error or assertion violation detected", proc.stdout)

if __name__ == "__main__":
    unittest.main()
