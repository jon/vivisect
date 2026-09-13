<!--
Copyright 2026 The Vivisect Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->
# Agent Guidelines for Vivisect

This document defines architectural standards, working directory discipline,
commit policies, formatting standards, and quality gates for AI agents
contributing to `vivisect`.

---

## 1. Architectural & Execution Principles

### Working Directory Discipline
- **NEVER run raw AMD tools (`vivado`, `xvlog`, `xelab`, `xsim`) directly in
  the workspace root.**
  AMD tools generate logs (`.log`, `.jou`, `.pb`), temp folders (`.Xil/`,
  `xsim.dir/`, `hd_visual/`), and lock files in their current working directory.
- All actions must execute inside a dedicated, disposable scratch directory
  inside the action's execution root:
  ```
  $PWD/_scratch_<action>_<uuid>/
  ```
- All action wrappers (`rules/support/run_isolated.py`) must guarantee that
  scratch directories are cleaned up unconditionally (via a Python `finally`
  block).
- All outputs (bitstreams, checkpoints, snapshots, logs) must be explicitly
  redirected or copied to Bazel's declared output files.

### Licensing Preservation
- AMD tools require license files (floating via FlexLM or node-locked in
  `~/.Xilinx/*.lic`).
- Do not purge license paths. Actions must respect `XILINXD_LICENSE_FILE` and
  `LM_LICENSE_FILE`.
- When isolating `$HOME` to prevent AMD tools from polluting the user's home
  directory, node-locked license files in `$REAL_HOME/.Xilinx` must be
  symlinked or made accessible.

### Code & Formatting Discipline
- **Markdown Line Length**: All Markdown prose, bullet lists, and paragraphs
  must strictly wrap at 80 characters or fewer.
- **Whitespace Discipline**: Zero trailing whitespace on any line across all
  source, configuration, and documentation files.
- **Newline Termination**: All files must conclude with a single trailing
  newline (`\n`).
- **Vendor Isolation**: Third-party vendored files (such as board constraints)
  must reside strictly in `vendor/**` and are excluded from repository style,
  linting, and formatting checks.

---

## 2. Commit Message Policy

We **do not use conventional commits** (no `feat:`, `chore:`, `fix:`, or type
prefixes).

We adhere to the classic Git / Linux kernel standard, with **Markdown
formatting permitted** in the commit body:

### Format
```text
Short (≤ 60 chars) capitalized summary in imperative mood

Provide a clear explanation of what this change does and why it was
necessary. Wrap prose paragraphs at approximately 72 characters. Focus
on context, architectural decisions, and trade-offs rather than repeating
the diff. Markdown formatting (code backticks, bullets, bolding) is
encouraged in the body.

- Highlight notable additions, flags, or configuration options
- Note any compatibility or hardware tool considerations
```

### Constraints
- Summary line must be in the imperative mood (e.g. `Add`, `Initialize`,
  `Implement`, `Fix`, not `Added`, `Initializes`, `Fixing`).
- Maximum 60 characters for the summary line.
- Leave one blank line between the summary and the body.
- Wrap paragraph text to 72 characters.
- Never prefix the summary with conventional commit types (`feat:`, `chore:`,
  etc.).

---

## 3. Mandatory Commit Gates

Before creating **any** git commit, agents must run and verify all six gates:

| Gate | Check / Command | Acceptance Criteria |
| :--- | :--- | :--- |
| **1. Build** | `bazel build //...` | Exits 0, zero build or analysis errors. |
| **2. Test** | `bazel test //...` | Exits 0, all automated tests pass. |
| **3. Format** | `bazel test //rules/test:style_test` | Exits 0, no trailing space, 80-col MD. |
| **4. Clean** | `git status --porcelain` | Workspace clean, no untracked artifacts. |
| **5. Diff** | `git diff --cached` | Reviewed line-by-line, intentional only. |
| **6. Docs** | Inspect `README.md` | Docs updated for new rules or targets. |

---

## 4. Tooling & Environment Context

- **Bazel**: Bazel 9+ with Bzlmod (`MODULE.bazel`). Bazelisk binary is located
  at `~/.local/bin/bazel`.
- **AMD Tools**: Located at `/tools/Xilinx/2026.1/Vivado/bin` (or sourced via
  `/tools/Xilinx/settings64.sh`).
- **Verilator**: Located at `/usr/bin/verilator` (v5.020+).
- **Python**: System Python 3 is used for action wrappers.
