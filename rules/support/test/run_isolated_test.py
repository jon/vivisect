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
import shutil
import stat
import subprocess
import tempfile
import unittest

RUN_ISOLATED = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "run_isolated.py")
)


class RunIsolatedTest(unittest.TestCase):

    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="test_run_isolated_")

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def run_wrapper(self, extra_args, cmd):
        full_cmd = [RUN_ISOLATED] + extra_args + ["--"] + cmd
        p = subprocess.run(
            full_cmd,
            cwd=self.test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return p.returncode, p.stdout, p.stderr

    def test_scratch_lifecycle_and_cleanup(self):
        rc, out, err = self.run_wrapper(
            ["--action-name", "lifecycle", "--verbose"],
            ["python3", "-c", "import os; print('CWD:', os.getcwd())"],
        )
        self.assertEqual(rc, 0)
        self.assertIn("_scratch_lifecycle_", out)
        # Verify no _scratch_ directory left behind in self.test_dir
        items = os.listdir(self.test_dir)
        self.assertEqual(items, [])

    def test_scratch_cleanup_on_error(self):
        rc, out, err = self.run_wrapper(
            ["--action-name", "fail_action"],
            ["python3", "-c", "import sys; sys.exit(42)"],
        )
        self.assertEqual(rc, 42)
        # Scratch directory must be cleaned up unconditionally
        items = os.listdir(self.test_dir)
        self.assertEqual(items, [])

    def test_output_file_copying(self):
        dest_file = os.path.join(self.test_dir, "extracted", "result.txt")
        rc, out, err = self.run_wrapper(
            [
                "--action-name", "file_copy",
                "--copy-output", f"sub/result.txt:{dest_file}",
            ],
            [
                "python3", "-c",
                "import os; os.makedirs('sub'); open('sub/result.txt', 'w').write('VALID OUTPUT')",
            ],
        )
        self.assertEqual(rc, 0)
        self.assertTrue(os.path.exists(dest_file))
        with open(dest_file) as f:
            self.assertEqual(f.read(), "VALID OUTPUT")
        # Ensure only extracted/ exists in test_dir, no scratch dir
        self.assertEqual(os.listdir(self.test_dir), ["extracted"])

    def test_sanitize_verilog_output(self):
        raw_stub = """// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2026.1 (lin64) Build 6511674 Tue Jun 16 11:01:26 MDT 2026
// Date        : Mon Sep 14 00:27:04 2026
// Host        : allium running 64-bit Ubuntu 24.04.4 LTS
// Command     : write_verilog -force -mode funcsim
//               /home/jon/.cache/bazel/.../_scratch_foo/bar.v
// Design      : test_mod
// Purpose     : Stub declaration
// Device      : xc7a100tcsg324-1
// --------------------------------------------------------------------------------
module test_mod(input clk, output q);
endmodule
"""
        dest_stub = os.path.join(self.test_dir, "sanitized", "test_stub.v")
        rc, out, err = self.run_wrapper(
            [
                "--action-name", "stub_sanitize",
                "--sanitize-verilog-output", f"raw_stub.v:{dest_stub}",
            ],
            [
                "python3", "-c",
                f"open('raw_stub.v', 'w').write('''{raw_stub}''')",
            ],
        )
        self.assertEqual(rc, 0)
        self.assertTrue(os.path.exists(dest_stub))
        with open(dest_stub) as f:
            sanitized = f.read()

        self.assertNotIn("Date        :", sanitized)
        self.assertNotIn("Host        :", sanitized)
        self.assertNotIn("Command     :", sanitized)
        self.assertNotIn("_scratch_foo", sanitized)
        self.assertIn("Tool Version: Vivado", sanitized)
        self.assertIn("Design      : test_mod", sanitized)
        self.assertIn("Device      : xc7a100tcsg324-1", sanitized)
        self.assertIn("module test_mod(input clk, output q);", sanitized)

    def test_output_directory_copying(self):
        dest_dir = os.path.join(self.test_dir, "extracted_dir")
        rc, out, err = self.run_wrapper(
            [
                "--action-name", "dir_copy",
                "--copy-dir-output", f"snap:{dest_dir}",
            ],
            [
                "python3", "-c",
                "import os; os.makedirs('snap/nested'); open('snap/nested/file.dat', 'w').write('DATA')",
            ],
        )
        self.assertEqual(rc, 0)
        self.assertTrue(os.path.isdir(dest_dir))
        nested_file = os.path.join(dest_dir, "nested", "file.dat")
        self.assertTrue(os.path.exists(nested_file))
        with open(nested_file) as f:
            self.assertEqual(f.read(), "DATA")

    def test_copy_input_dir_preserves_executable_permissions(self):
        # Create a mock snapshot directory with an executable binary and a data file
        input_snap = os.path.join(self.test_dir, "input_snap")
        os.makedirs(input_snap, exist_ok=True)
        exe_path = os.path.join(input_snap, "xsimk")
        with open(exe_path, "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(exe_path, 0o755)

        data_path = os.path.join(input_snap, "data.txt")
        with open(data_path, "w") as f:
            f.write("hello")
        os.chmod(data_path, 0o644)

        # Make input directory read-only (0555) to emulate Bazel sandbox input
        os.chmod(input_snap, 0o555)

        rc, out, err = self.run_wrapper(
            [
                "--action-name", "copy_in_test",
                "--verbose",
                "--copy-input-dir", f"{input_snap}:staged_snap",
            ],
            [
                "python3", "-c",
                "import os, stat; "
                "st = os.stat('staged_snap/xsimk'); "
                "assert bool(st.st_mode & stat.S_IXUSR), 'Executable bit not preserved'; "
                "open('staged_snap/new_file.txt', 'w').write('WRITABLE'); "
                "print('COPY_IN_OK')",
            ],
        )
        # Restore permissions so tearDown can remove it
        os.chmod(input_snap, 0o755)
        self.assertEqual(rc, 0)
        self.assertIn("COPY_IN_OK", out)

    def test_copy_input_file(self):
        input_file = os.path.join(self.test_dir, "init.coe")
        with open(input_file, "w") as f:
            f.write("COE_DATA_123")

        rc, out, err = self.run_wrapper(
            [
                "--action-name", "copy_file_test",
                "--verbose",
                "--copy-input", f"{input_file}:nested/staged.coe",
            ],
            [
                "python3", "-c",
                "import os; "
                "assert os.path.exists('nested/staged.coe'); "
                "content = open('nested/staged.coe').read(); "
                "assert content == 'COE_DATA_123'; "
                "open('nested/staged.coe', 'a').write('_APPENDED'); "
                "print('COPY_FILE_OK')",
            ],
        )
        self.assertEqual(rc, 0)
        self.assertIn("COPY_FILE_OK", out)

    def test_log_file_capture(self):
        log_file = os.path.join(self.test_dir, "run.log")
        rc, out, err = self.run_wrapper(
            ["--action-name", "logger", "--log-file", log_file],
            ["python3", "-c", "print('LOGGED MESSAGE')"],
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertEqual(err, "")
        self.assertTrue(os.path.exists(log_file))
        with open(log_file) as f:
            content = f.read()
            self.assertIn("LOGGED MESSAGE", content)

    def test_silent_on_success_by_default(self):
        rc, out, err = self.run_wrapper(
            ["--action-name", "silent"],
            ["python3", "-c", "import sys; print('SHOULD_BE_SILENT'); sys.stderr.write('ALSO_SILENT\\n')"],
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertEqual(err, "")

    def test_flushes_to_stderr_on_failure(self):
        rc, out, err = self.run_wrapper(
            ["--action-name", "fail_dump"],
            ["python3", "-c", "import sys; print('DIAGNOSTIC_FAILURE_MSG'); sys.exit(7)"],
        )
        self.assertEqual(rc, 7)
        self.assertEqual(out, "")
        self.assertIn("DIAGNOSTIC_FAILURE_MSG", err)

    def test_verbose_streams_to_stdout(self):
        rc, out, err = self.run_wrapper(
            ["--action-name", "verbose_test", "--verbose"],
            ["python3", "-c", "print('VERBOSE_STREAM')"],
        )
        self.assertEqual(rc, 0)
        self.assertIn("VERBOSE_STREAM", out)
        self.assertEqual(err, "")

    def test_environment_and_license_isolation(self):
        rc, out, err = self.run_wrapper(
            ["--action-name", "env_test", "--verbose"],
            [
                "python3", "-c",
                "import os; print('XIL:', os.environ.get('XILINX_LOCAL_USER_DATA')); print('HOME:', os.environ.get('HOME'))",
            ],
        )
        self.assertEqual(rc, 0)
        self.assertIn("XIL: no", out)
        self.assertIn("_scratch_env_test_", out)

    def test_concurrent_execution_stress(self):
        import concurrent.futures
        num_workers = 20
        results = {}

        def worker(idx):
            dest_file = os.path.join(self.test_dir, f"result_{idx}.txt")
            rc, out, err = self.run_wrapper(
                [
                    "--action-name", f"stress_{idx}",
                    "--copy-output", f"out.txt:{dest_file}",
                ],
                [
                    "python3", "-c",
                    f"import time; time.sleep(0.05); open('out.txt', 'w').write('WORKER_{idx}')",
                ],
            )
            return idx, rc, dest_file

        with concurrent.futures.ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker, i) for i in range(num_workers)]
            for fut in concurrent.futures.as_completed(futures):
                idx, rc, dest = fut.result()
                results[idx] = (rc, dest)

        # Verify all 20 completed successfully
        self.assertEqual(len(results), num_workers)
        for idx in range(num_workers):
            rc, dest = results[idx]
            self.assertEqual(rc, 0, f"Worker {idx} failed with returncode {rc}")
            self.assertTrue(os.path.exists(dest), f"Result file missing for worker {idx}")
            with open(dest) as f:
                self.assertEqual(f.read(), f"WORKER_{idx}")

        # Verify no scratch directories remain
        remaining = [f for f in os.listdir(self.test_dir) if f.startswith("_scratch_")]
        self.assertEqual(remaining, [], f"Scratch directories leaked: {remaining}")


if __name__ == "__main__":
    unittest.main()

