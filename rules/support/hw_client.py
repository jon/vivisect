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

"""Hardware communication client for FPGA testing and serial verification.

Provides serial port discovery, auto-detection of Digilent / FTDI USB devices,
and bidirectional UART communication with pattern assertion support. Uses
pyserial when available with automatic fallback to standard POSIX termios.
"""

import glob
import os
import re
import select
import sys
import time

try:
    import serial
    _HAVE_PYSERIAL = True
except ImportError:
    _HAVE_PYSERIAL = False

try:
    import termios
    import tty
    _HAVE_TERMIOS = True
except ImportError:
    _HAVE_TERMIOS = False


def detect_uart_port(preferred: str = "auto") -> str:
    """Resolve physical UART port path from preferred setting or auto-detection.

    Args:
        preferred: Explicit port path, or 'auto' to auto-detect.

    Returns:
        Canonical filesystem path to the serial device.
    """
    env_port = os.environ.get("VIVISECT_UART_PORT")
    if env_port:
        return env_port

    if preferred and preferred != "auto":
        return preferred

    # 1. Search /dev/serial/by-id/ for Digilent or FTDI devices
    by_id_dir = "/dev/serial/by-id"
    if os.path.isdir(by_id_dir):
        # Look for Digilent UART channel (typically if01 on dual-channel FT2232)
        digilent_candidates = glob.glob(os.path.join(by_id_dir, "*Digilent*if01*"))
        if not digilent_candidates:
            digilent_candidates = glob.glob(os.path.join(by_id_dir, "*Digilent*"))
        if not digilent_candidates:
            digilent_candidates = glob.glob(os.path.join(by_id_dir, "*FTDI*if01*"))
        if not digilent_candidates:
            digilent_candidates = glob.glob(os.path.join(by_id_dir, "*FTDI*"))
        if not digilent_candidates:
            digilent_candidates = glob.glob(os.path.join(by_id_dir, "*usb*"))

        if digilent_candidates:
            return os.path.realpath(digilent_candidates[0])

    # 2. Check standard device nodes
    for node in ["/dev/ttyUSB1", "/dev/ttyUSB0", "/dev/ttyACM0"]:
        if os.path.exists(node):
            return node

    return "/dev/ttyUSB1"


class PosixSerial:
    """Minimal POSIX termios serial port implementation without external dependencies."""

    def __init__(self, port: str, baudrate: int = 115200, timeout: float = 1.0):
        if not _HAVE_TERMIOS:
            raise RuntimeError("POSIX termios is not available on this platform.")
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.fd = None
        self._old_attr = None

    def open(self):
        baud_map = {
            9600: termios.B9600,
            19200: termios.B19200,
            38400: termios.B38400,
            57600: termios.B57600,
            115200: termios.B115200,
            230400: termios.B230400,
        }
        baud = baud_map.get(self.baudrate, termios.B115200)

        self.fd = os.open(self.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        self._old_attr = termios.tcgetattr(self.fd)

        tty.setraw(self.fd)
        attr = termios.tcgetattr(self.fd)
        attr[4] = baud  # ispeed
        attr[5] = baud  # ospeed
        # 8N1 raw mode
        attr[0] = 0     # iflag
        attr[1] = 0     # oflag
        attr[2] = termios.CS8 | termios.CREAD | termios.CLOCAL  # cflag
        attr[3] = 0     # lflag
        attr[6][termios.VMIN] = 0
        attr[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, attr)

    def write(self, data: bytes):
        if self.fd is None:
            raise RuntimeError("Port not open")
        return os.write(self.fd, data)

    def read(self, size: int = 1) -> bytes:
        if self.fd is None:
            raise RuntimeError("Port not open")
        r, _, _ = select.select([self.fd], [], [], self.timeout)
        if r:
            return os.read(self.fd, size)
        return b""

    def read_nonblocking(self, size: int = 1024) -> bytes:
        if self.fd is None:
            raise RuntimeError("Port not open")
        r, _, _ = select.select([self.fd], [], [], 0)
        if r:
            try:
                return os.read(self.fd, size)
            except OSError:
                return b""
        return b""

    def close(self):
        if self.fd is not None:
            if self._old_attr:
                try:
                    termios.tcsetattr(self.fd, termios.TCSANOW, self._old_attr)
                except OSError:
                    pass
            try:
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None


class UartClient:
    """High-level UART client for FPGA hardware assertion and testing."""

    def __init__(
        self,
        port: str = "auto",
        baudrate: int = 115200,
        timeout: float = 10.0,
    ):
        self.port = detect_uart_port(port)
        self.baudrate = int(baudrate)
        self.timeout = float(timeout)
        self._conn = None

    def open(self):
        """Open serial port connection."""
        if _HAVE_TERMIOS:
            try:
                conn = PosixSerial(
                    port=self.port,
                    baudrate=self.baudrate,
                    timeout=min(self.timeout, 1.0),
                )
                conn.open()
                self._conn = conn
                return
            except Exception as err:
                sys.stderr.write(
                    f"UartClient: PosixSerial failed ({err}), trying pyserial fallback...\n"
                )

        if _HAVE_PYSERIAL:
            try:
                self._conn = serial.Serial(
                    port=self.port,
                    baudrate=self.baudrate,
                    timeout=min(self.timeout, 1.0),
                )
                return
            except Exception as err:
                sys.stderr.write(f"UartClient: pyserial failed ({err})\n")

        raise RuntimeError(
            f"Unable to open serial port {self.port}: Neither termios nor pyserial available."
        )

    def close(self):
        """Close serial port connection."""
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
            self._conn = None

    def send(self, data) -> int:
        """Send byte array or string over serial interface."""
        if isinstance(data, str):
            data = data.encode("utf-8")
        if self._conn is None:
            raise RuntimeError("Serial connection not open")
        return self._conn.write(data)

    def read(self, size: int = 1) -> bytes:
        """Read up to size bytes."""
        if self._conn is None:
            raise RuntimeError("Serial connection not open")
        try:
            return self._conn.read(size)
        except Exception:
            return b""


    def read_all(self) -> str:
        """Non-blocking read of immediately available buffered data."""
        if self._conn is None:
            return ""
        if hasattr(self._conn, "read_nonblocking"):
            data = self._conn.read_nonblocking(4096)
            return data.decode("utf-8", errors="replace")
        if hasattr(self._conn, "in_waiting") and self._conn.in_waiting > 0:
            data = self._conn.read(self._conn.in_waiting)
            return data.decode("utf-8", errors="replace")
        return ""

    def expect(
        self,
        pattern: str,
        timeout: float = None,
        regex: bool = True,
    ) -> str:
        """Read serial stream until pattern matches or timeout occurs.

        Args:
            pattern: Target string or regex pattern to search for.
            timeout: Maximum seconds to wait (defaults to client timeout).
            regex: Whether pattern should be interpreted as regular expression.

        Returns:
            The complete accumulated buffer containing the match.

        Raises:
            TimeoutError: If the pattern is not matched before timeout.
        """
        eff_timeout = timeout if timeout is not None else self.timeout
        start_time = time.time()
        accumulated = ""
        compiled = re.compile(pattern) if regex else None

        while True:
            chunk = self.read(64)
            if chunk:
                text = chunk.decode("utf-8", errors="replace")
                accumulated += text

                matched = False
                if regex:
                    if compiled.search(accumulated):
                        matched = True
                else:
                    if pattern in accumulated:
                        matched = True

                if matched:
                    return accumulated

            elapsed = time.time() - start_time
            if elapsed >= eff_timeout:
                clean_accum = repr(accumulated)
                raise TimeoutError(
                    f"Timed out after {eff_timeout:.1f}s waiting for serial pattern "
                    f"'{pattern}'. Received buffer: {clean_accum}"
                )

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
