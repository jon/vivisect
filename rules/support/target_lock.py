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

"""Target device mutual exclusion and stale-lock recovery manager.

Provides kernel-backed advisory locking via fcntl.flock combined with
process table interrogation to guarantee exclusive hardware target access
across concurrent Bazel actions, external test scripts, and shell sessions.
Automatically recovers from stale locks caused by terminated or crashed processes.
"""

import errno
import fcntl
import json
import os
import re
import socket
import sys
import time


def sanitize_target_id(target_id: str) -> str:
    """Sanitize a target identifier or path for safe filesystem naming."""
    clean = re.sub(r"[^A-Za-z0-9_.-]", "_", target_id)
    return clean.strip("_") or "default"


_HELD_LOCKS = {}


class TargetLock:
    """Manages exclusive access to a hardware target with stale-lock recovery."""

    def __init__(
        self,
        target_id: str,
        timeout: float = 60.0,
        lock_dir: str = "/tmp",
        poll_interval: float = 0.5,
    ):
        self.target_id = target_id
        self.timeout = float(timeout)
        self.lock_dir = lock_dir
        self.poll_interval = float(poll_interval)
        self.safe_id = sanitize_target_id(target_id)
        self.lock_path = os.path.join(
            self.lock_dir, f"vivisect_lock_{self.safe_id}.lock"
        )
        self._fd = None
        self._acquired = False

    def is_pid_alive(self, pid: int) -> bool:
        """Check if a process with given PID exists in OS process table."""
        if pid <= 0:
            return False
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True

    def read_metadata(self) -> dict:
        """Attempt to read lock holder metadata from lockfile."""
        try:
            if os.path.exists(self.lock_path):
                with open(self.lock_path, "r", encoding="utf-8") as f:
                    content = f.read().strip()
                    if content:
                        return json.loads(content)
        except Exception:
            pass
        return {}

    def acquire(self) -> bool:
        """Acquire exclusive lock on target, recovering from stale locks if needed."""
        if os.environ.get("VIVISECT_NO_TARGET_LOCK") == "1":
            self._acquired = True
            return True

        # Check re-entrancy within current process
        if self.lock_path in _HELD_LOCKS:
            fd, depth = _HELD_LOCKS[self.lock_path]
            _HELD_LOCKS[self.lock_path] = (fd, depth + 1)
            self._fd = fd
            self._acquired = True
            return True

        os.makedirs(self.lock_dir, exist_ok=True)
        start_time = time.time()
        last_logged_pid = None

        while True:
            try:
                fd = os.open(
                    self.lock_path, os.O_RDWR | os.O_CREAT, 0o666
                )
            except OSError as err:
                sys.stderr.write(
                    f"TargetLock: Failed to open lockfile {self.lock_path}: {err}\n"
                )
                raise

            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                # Lock acquired successfully
                self._fd = fd
                self._acquired = True
                _HELD_LOCKS[self.lock_path] = (fd, 1)

                # Write ownership metadata
                metadata = {
                    "pid": os.getpid(),
                    "hostname": socket.gethostname(),
                    "timestamp": time.time(),
                    "command": " ".join(sys.argv),
                    "target": self.target_id,
                }
                try:
                    os.ftruncate(fd, 0)
                    os.lseek(fd, 0, os.SEEK_SET)
                    os.write(
                        fd, json.dumps(metadata, indent=2).encode("utf-8")
                    )
                except OSError:
                    pass
                return True

            except (BlockingIOError, OSError) as err:
                # Handle contention
                if (
                    isinstance(err, BlockingIOError)
                    or err.errno in (errno.EACCES, errno.EAGAIN)
                ):
                    meta = self.read_metadata()
                    holder_pid = meta.get("pid")

                    if holder_pid and not self.is_pid_alive(holder_pid):
                        # Stale lock holder detected
                        sys.stderr.write(
                            f"TargetLock: Detected stale lock on '{self.target_id}' "
                            f"from deceased PID {holder_pid}. Reclaiming lock.\n"
                        )
                        try:
                            os.close(fd)
                        except OSError:
                            pass
                        try:
                            os.unlink(self.lock_path)
                        except OSError:
                            pass
                        time.sleep(0.05)
                        continue

                    # Active holder exists, check timeout
                    elapsed = time.time() - start_time
                    if elapsed >= self.timeout:
                        os.close(fd)
                        cmd = meta.get("command", "unknown")
                        raise TimeoutError(
                            f"Timed out after {self.timeout:.1f}s waiting for exclusive "
                            f"lock on hardware target '{self.target_id}'. Currently held "
                            f"by PID {holder_pid} ({cmd})."
                        )

                    if holder_pid != last_logged_pid:
                        sys.stderr.write(
                            f"TargetLock: Hardware target '{self.target_id}' is locked "
                            f"by PID {holder_pid}. Waiting up to {self.timeout:.0f}s...\n"
                        )
                        last_logged_pid = holder_pid

                    os.close(fd)
                    time.sleep(self.poll_interval)
                else:
                    os.close(fd)
                    raise

    def release(self):
        """Release exclusive lock on target."""
        if not self._acquired:
            return

        if self.lock_path in _HELD_LOCKS:
            fd, depth = _HELD_LOCKS[self.lock_path]
            if depth > 1:
                _HELD_LOCKS[self.lock_path] = (fd, depth - 1)
                self._acquired = False
                self._fd = None
                return
            del _HELD_LOCKS[self.lock_path]

        if self._fd is not None:
            try:
                try:
                    os.ftruncate(self._fd, 0)
                except OSError:
                    pass
                fcntl.flock(self._fd, fcntl.LOCK_UN)
                os.close(self._fd)
            except OSError:
                pass
            finally:
                self._fd = None
                self._acquired = False

    def __enter__(self):
        self.acquire()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.release()
