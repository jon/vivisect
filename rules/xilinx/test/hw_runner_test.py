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

"""Unit tests for TargetLock, UartClient, and hardware runners."""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

from rules.support.target_lock import TargetLock, sanitize_target_id
from rules.support.hw_client import detect_uart_port, UartClient
import rules.support.hw_program_runner as hw_program_runner
import rules.support.hw_test_runner as hw_test_runner


class TargetLockTest(unittest.TestCase):
    """Verifies TargetLock mutual exclusion and stale lock recovery."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.lock_dir = self.tmp_dir.name

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_sanitize_target_id(self):
        self.assertEqual(sanitize_target_id("localhost:3121/target_1"), "localhost_3121_target_1")
        self.assertEqual(sanitize_target_id("/dev/ttyUSB1"), "dev_ttyUSB1")
        self.assertEqual(sanitize_target_id(""), "default")

    def test_acquire_and_release(self):
        lock = TargetLock("test_target", timeout=2.0, lock_dir=self.lock_dir)
        self.assertTrue(lock.acquire())
        self.assertTrue(os.path.exists(lock.lock_path))

        meta = lock.read_metadata()
        self.assertEqual(meta.get("pid"), os.getpid())
        self.assertEqual(meta.get("target"), "test_target")

        lock.release()
        self.assertFalse(lock._acquired)

    def test_context_manager(self):
        with TargetLock("ctx_target", timeout=2.0, lock_dir=self.lock_dir) as lock:
            self.assertTrue(lock._acquired)
            self.assertTrue(os.path.exists(lock.lock_path))
        self.assertFalse(lock._acquired)

    def test_reentrancy(self):
        lock1 = TargetLock("reentrant_target", timeout=2.0, lock_dir=self.lock_dir)
        self.assertTrue(lock1.acquire())
        lock2 = TargetLock("reentrant_target", timeout=2.0, lock_dir=self.lock_dir)
        self.assertTrue(lock2.acquire())
        lock2.release()
        self.assertTrue(lock1._acquired)
        lock1.release()
        self.assertFalse(lock1._acquired)

    def test_stale_lock_recovery(self):
        """Verify that a lockfile held by a deceased PID is automatically reclaimed."""
        target = "stale_target"
        safe_id = sanitize_target_id(target)
        lock_path = os.path.join(self.lock_dir, f"vivisect_lock_{safe_id}.lock")

        # Fake dead PID (999999 is extraordinarily unlikely to exist)
        dead_pid = 999999
        fake_meta = {
            "pid": dead_pid,
            "hostname": "test-host",
            "timestamp": time.time() - 3600,
            "command": "fake_test_runner",
            "target": target,
        }
        with open(lock_path, "w", encoding="utf-8") as f:
            f.write(json.dumps(fake_meta))

        # Attempt to acquire lock on the same target
        lock = TargetLock(target, timeout=2.0, lock_dir=self.lock_dir)
        self.assertTrue(lock.acquire())
        self.assertTrue(lock._acquired)

        # Confirm ownership was updated to current process
        meta = lock.read_metadata()
        self.assertEqual(meta.get("pid"), os.getpid())
        lock.release()


class HwClientTest(unittest.TestCase):
    """Verifies UartClient and port resolution."""

    def test_detect_uart_port_override(self):
        os.environ["VIVISECT_UART_PORT"] = "/dev/custom_uart"
        try:
            self.assertEqual(detect_uart_port("auto"), "/dev/custom_uart")
            self.assertEqual(detect_uart_port("/dev/explicit"), "/dev/custom_uart")
        finally:
            del os.environ["VIVISECT_UART_PORT"]

    def test_detect_uart_port_explicit(self):
        self.assertEqual(detect_uart_port("/dev/ttyUSB42"), "/dev/ttyUSB42")


class ProgramRunnerTest(unittest.TestCase):
    """Verifies Tcl generation and mock programming."""

    def test_generate_sram_tcl_script(self):
        tcl = hw_program_runner.generate_sram_program_tcl(
            bitstream_path="/path/to/design.bit",
            probes_path="/path/to/debug.ltx",
            hw_server_url="localhost:3121",
            target_pattern="210319AE1CDC",
            device_pattern="xc7a100t_0",
            part="xc7a100tcsg324-1",
            tcl_pre=["/pre/hook.tcl"],
            tcl_post=["/post/hook.tcl"],
        )
        self.assertIn("open_hw_manager", tcl)
        self.assertIn("connect_hw_server -url localhost:3121", tcl)
        self.assertIn("210319AE1CDC", tcl)
        self.assertIn("xc7a100t_0", tcl)
        self.assertIn("/path/to/design.bit", tcl)
        self.assertIn("/path/to/debug.ltx", tcl)
        self.assertIn("source \"/pre/hook.tcl\"", tcl)
        self.assertIn("program_hw_devices", tcl)
        self.assertIn("REGISTER.CONFIG_STATUS.BIT14_DONE_PIN", tcl)
        self.assertIn("source \"/post/hook.tcl\"", tcl)
        self.assertIn("close_hw_manager", tcl)

    def test_mock_program_runner(self):
        rc = hw_program_runner.main([
            "--bitstream", "/tmp/fake.bit",
            "--part", "xc7a100t",
            "--mock",
        ])
        self.assertEqual(rc, 0)


class TestRunnerTest(unittest.TestCase):
    """Verifies HIL test harness in mock mode."""

    def test_mock_hil_done_only(self):
        rc = hw_test_runner.main([
            "--bitstream", "/tmp/fake.bit",
            "--part", "xc7a100t",
            "--mode", "done_only",
            "--mock",
        ])
        self.assertEqual(rc, 0)

    def test_mock_hil_uart(self):
        rc = hw_test_runner.main([
            "--bitstream", "/tmp/fake.bit",
            "--part", "xc7a100t",
            "--mode", "uart",
            "--uart-expect", "ROK",
            "--uart-expect", "Pass",
            "--uart-send", "START",
            "--mock",
        ])
        self.assertEqual(rc, 0)

    def test_mock_hil_tcl(self):
        rc = hw_test_runner.main([
            "--bitstream", "/tmp/fake.bit",
            "--part", "xc7a100t",
            "--mode", "tcl",
            "--tcl-test", "/tmp/test.tcl",
            "--mock",
        ])
        self.assertEqual(rc, 0)

    def test_mock_hil_runner(self):
        rc = hw_test_runner.main([
            "--bitstream", "/tmp/fake.bit",
            "--part", "xc7a100t",
            "--mode", "runner",
            "--test-runner", "/bin/true",
            "--mock",
        ])
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
