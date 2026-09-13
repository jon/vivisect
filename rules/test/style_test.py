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

"""Automated formatting, whitespace, and Markdown style enforcement test."""

import os
import unittest


def discover_workspace_root():
    """Locate the canonical workspace root directory."""
    if "BUILD_WORKSPACE_DIRECTORY" in os.environ:
        return os.environ["BUILD_WORKSPACE_DIRECTORY"]

    cur = os.getcwd()
    while cur and cur != "/":
        bzl = os.path.join(cur, "BUILD.bazel")
        if os.path.exists(bzl):
            return os.path.dirname(os.path.realpath(bzl))
        cur = os.path.dirname(cur)

    # Fallback to current working directory
    return os.getcwd()


class StyleTest(unittest.TestCase):
    """Enforces workspace style discipline across all non-vendored sources."""

    def setUp(self):
        self.workspace_root = discover_workspace_root()
        self.assertTrue(
            os.path.isdir(self.workspace_root),
            f"Workspace root does not exist: {self.workspace_root}",
        )

    def test_repository_style_conformance(self):
        ignored_dir_names = {
            ".git",
            ".idea",
            ".vscode",
            "_tmp",
            "__pycache__",
            ".pytest_cache",
        }
        ignored_extensions = {
            ".lock",
            ".dcp",
            ".bit",
            ".bin",
            ".wdb",
            ".pb",
            ".png",
            ".jpg",
            ".ico",
            ".pyc",
            ".pyo",
        }

        violations = []

        for root, dirs, files in os.walk(self.workspace_root):
            # Prune ignored and scratch/build directories
            dirs[:] = [
                d
                for d in dirs
                if d not in ignored_dir_names
                and not d.startswith("bazel-")
                and not d.startswith("_scratch_")
            ]

            rel_dir = os.path.relpath(root, self.workspace_root)
            # Strictly exclude all vendored assets from style checks
            if rel_dir == "vendor" or rel_dir.startswith("vendor" + os.sep):
                continue

            for fname in files:
                if fname.startswith("."):
                    if fname not in {".bazelrc", ".bazelignore", ".gitignore"}:
                        continue

                _, ext = os.path.splitext(fname)
                if ext in ignored_extensions:
                    continue

                fpath = os.path.join(root, fname)
                rel_path = os.path.relpath(fpath, self.workspace_root)

                # Skip broken symlinks or missing files
                if not os.path.isfile(fpath):
                    continue

                try:
                    with open(fpath, "rb") as fp:
                        raw_data = fp.read()
                except Exception as err:
                    violations.append(f"{rel_path}: Failed to read ({err})")
                    continue

                if not raw_data:
                    continue

                # 1. Enforce final newline
                if not raw_data.endswith(b"\n"):
                    violations.append(
                        f"{rel_path}: Missing terminating newline character"
                    )

                try:
                    text_content = raw_data.decode("utf-8")
                except UnicodeDecodeError:
                    # Non-UTF-8 binary files are skipped
                    continue

                lines = text_content.splitlines()
                is_markdown = fname.endswith(".md")
                in_code_block = False

                for line_idx, line in enumerate(lines, 1):
                    # 2. Enforce zero trailing whitespace
                    if line.endswith(" ") or line.endswith("\t"):
                        violations.append(
                            f"{rel_path}:{line_idx}: Trailing whitespace detected"
                        )

                    # 3. Enforce Markdown line length <= 80 characters
                    if is_markdown:
                        stripped = line.strip()
                        if stripped.startswith("```"):
                            in_code_block = not in_code_block
                            continue
                        if in_code_block:
                            continue
                        # Tables, HTML comments, and pure link definitions are exempt
                        if stripped.startswith("|") and stripped.endswith("|"):
                            continue
                        if stripped.startswith("<!--") or stripped.endswith("-->"):
                            continue
                        if len(line) > 80:
                            violations.append(
                                f"{rel_path}:{line_idx}: Line exceeds 80 characters "
                                f"({len(line)} > 80): {line[:50]}..."
                            )

        if violations:
            msg = f"\nFound {len(violations)} style violation(s):\n" + "\n".join(
                f"  - {v}" for v in violations[:50]
            )
            if len(violations) > 50:
                msg += f"\n  ... and {len(violations) - 50} more"
            self.fail(msg)


if __name__ == "__main__":
    unittest.main()
