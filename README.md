# Vivisect

Bazel rules for AMD FPGA development and hardware simulation, integrating
AMD Vivado (`xvlog`, `xelab`, `xsim`, `vivado`) and Verilator with modern
Bazel (Bzlmod).

## Overview

Hardware development workflows frequently suffer from monolithic,
non-incremental scripts and invasive tool behavior. Vivisect bridges AMD
FPGA tooling and Verilator into Bazel:

- **Isolated & Silent Execution**: Strict per-action scratch directories
  eliminate EDA file spew (`.Xil/`, `*.log`, `*.jou`, `*.pb`) in workspace
  directories, while suppressing compiler and tool banners on success to
  adhere to Bazel's silence-on-success discipline. Detailed logs are
  preserved in declared `.log` artifacts and flushed to `stderr` on failure.
- **Incremental Multi-Stage Caching**: Decomposes synthesis, placement &
  routing, and bitstream generation into cached Design Checkpoint (`.dcp`)
  stages.
- **Target-Stage Transitions (`select()` support)**: Automatic incoming
  transitions allow SystemVerilog code to select between synthesis stubs,
  simulation netlists, and Verilator models without CLI flags or cache churn.
- **Licensing Preservation**: Forwards floating and node-locked license
  configurations without exposing user directories to corruption.

---

## Prerequisites

- **Bazel 9+** (configured via Bzlmod in `MODULE.bazel`)
- **AMD Vivado 2026.1+** (or compatible Vivado ML edition installed at
  `/tools/Xilinx/2026.1/Vivado/bin` or sourced via `settings64.sh`)
- **Verilator 5.020+** (installed on `$PATH` at `/usr/bin/verilator`)
- **Python 3.10+** (system Python used for action isolation wrappers)

## Quickstart

Run the full automated test suite:
```bash
bazel test //...
```

---

## Execution Profiles & Hermeticity

Vivisect supports two execution profiles configured in `.bazelrc`:

### Sandboxed Execution (Default)
Actions execute inside Bazel's sandbox. Host toolchains are mounted explicitly:
```bash
# Defined in .bazelrc
build --sandbox_add_mount=/tools/Xilinx
build --action_env=XILINXD_LICENSE_FILE
build --action_env=LM_LICENSE_FILE
```

### Local Execution (`--config=local`)
Actions execute directly on the host without sandboxing:
```bash
bazel test --config=local //...
```

---

## Licensing & Toolchain Integration

Vivisect orchestrates host-installed AMD Vivado and Verilator tools while
preserving existing floating and node-locked licenses:

- **Floating Licenses**: Forwarded via `XILINXD_LICENSE_FILE` or
  `LM_LICENSE_FILE` action environment variables.
- **Node-Locked Licenses**: Preserved via `$HOME/.Xilinx` mounts into
  isolated execution environments.
- **Silence on Success**: Tool execution logs are captured silently and
  written to declared log files. Stderr diagnostics are flushed automatically
  if an action fails. Interactive debug mode is available with `--verbose`.

---

## Target-Stage Transitions

Vivisect uses a custom build setting `//rules:stage` to automatically select
appropriate target variants across build phases:

| Stage | Intended Usage | Rule Behavior |
| :--- | :--- | :--- |
| `synthesis` | FPGA synthesis & implementation | Direct RTL or synthesis stubs |
| `simulation` | Vivado `xsim` simulation | Full RTL or simulation netlists |
| `verilator` | Verilator linting & C++ transpilation | Transpiles or lints via Verilator |

SystemVerilog libraries can provide stage-dependent implementations using
standard `select()` statements on the stage label.

---

## Hardware Starlark Providers

Vivisect defines typed Starlark providers in `rules/providers.bzl` to propagate
hardware build artifacts across rule boundaries:

- `SvInfo`: Transitive SystemVerilog sources, headers, include directories,
  defines, and waivers with postorder dependency ordering.
- `VivadoDcpInfo`: Checkpoint (`.dcp`) files, structural Verilog netlists, and
  sanitized black-box stubs.
- `VivadoConstraintsInfo`: Stage-scoped design constraints (`synth`, `impl`,
  `scoped`).
- `VivadoPartInfo`: Canonical silicon part specification (`device`, `package`,
  `speed`).
- `VivadoBoardInfo`: Board-level part bindings and master constraint libraries.
- `XsimSnapshotInfo`: Compiled snapshot artifacts from `xelab`.
- `VerilatorCppInfo`: C++ sources transpiled by Verilator and include
  directories.
- `TclInfo`: Transitive Tcl scripts and hooks.

---

## SystemVerilog & Verilator Rules

Vivisect models SystemVerilog structures with explicit compile ordering:

### `sv_library`
Compiles SystemVerilog modules and tracks preprocessor include directories.

```starlark
load("//rules:defs.bzl", "sv_library")

sv_library(
    name = "counter",
    srcs = ["rtl/counter.sv"],
    deps = [":counter_pkg"],
)
```

### `sv_package`
Encapsulates shared SystemVerilog packages (`package ... endpackage`). Packages
are guaranteed to precede modules during compilation and elaboration.

### `sv_interface`
Encapsulates SystemVerilog interfaces (`interface ... endinterface`).

### `verilator_lint_test`
Runs Verilator static lint checks with `--lint-only` without compiler banner
noise. Generates synthetic stubs when linting packages and interfaces in
isolation.

### `verilator_test`
Simulates SystemVerilog designs using Verilator with two testing modes:
- **`waivers`**: Verilator `.vlt` configuration and waiver files forwarded to
  the underlying `verilator_library`.
- **Pure SystemVerilog Testbench (`tb = None`)**: When `tb` is omitted,
  simulates the top-level SystemVerilog testbench module directly using
  Verilator 5's `--timing` engine and auto-generated `main()` event loop. This
  matches the target contract of `xsim_test`, allowing the exact same
  testbench library to run across both simulators.
- **C++ Testbench (`tb = "my_tb.cpp"`)**: Transpiles the DUT into C++ and
  compiles `tb` as the test executable driver.

---

## AMD Simulation & Elaboration Rules

### `xsim_test`
Executes elaborated simulation snapshots under `xsim` with native multi-line
error trapping.

- `waveforms = True`: Automatically captures signals and exports `<name>.wdb`.
- `libs = ["unisims_ver"]`: UNISIM library dependencies automatically enable
  `glbl` elaboration and bind `glbl.v` from the toolchain.

### `xelab`
Elaborates SystemVerilog/Verilog sources into an `xsim.dir/<snapshot>` artifact.

- `libs`: Simulation libraries passed to `-L` (e.g. `["unisims_ver"]`).
- `Standard glbl.v support`: When `"unisims_ver"` is specified in `libs` or
  `"glbl"` is in `tops`, `xelab` automatically appends `-top glbl` and
  compiles Vivado's standard `glbl.v` (resolved from the Vivado toolchain) via
  `-svlog`, unless user sources already define `glbl.v`.

### `xvlog`
Compiles SystemVerilog/Verilog sources into an xsim library.

- `glbl = True`: Automatically includes and compiles Vivado's standard `glbl.v`
  into the generated library.

## Repository Layout

```
├── MODULE.bazel                 # Bzlmod module definition & toolchains
├── .bazelrc                     # Build configurations & licensing flags
├── AGENTS.md                    # Agent guidelines & commit gates
├── BUILD.bazel                  # Root package declaration & style sources
├── LICENSE                      # Apache License, Version 2.0
├── NOTICE                       # Copyright attribution & third-party notices
├── README.md                    # Workspace overview and documentation
├── rules/
│   ├── defs.bzl                 # Public API entrypoint
│   ├── providers.bzl            # Hardware Starlark providers
│   ├── stage.bzl                # Stage transitions & build setting
│   ├── support/                 # run_isolated.py runner and unit tests
│   ├── sv/                      # sv_library, verilator rules & tests
│   ├── test/                    # providers_test and style_test
│   ├── toolchains/              # Vivado and Verilator toolchains
│   └── xilinx/                  # xvlog, xelab, xsim_test & simulation tests
└── examples/
    └── counter/                 # Parameterized counter RTL & dual-sim tests
```

## Contributing & Agent Guidelines

See [AGENTS.md](AGENTS.md) for commit message specifications (classic Git /
Linux kernel style with Markdown permitted), commit gates, formatting
standards, and execution requirements.

## License

Vivisect is licensed under the [Apache License, Version 2.0](LICENSE).

Copyright 2026 The Vivisect Authors.

For third-party attributions and notices, see [NOTICE](NOTICE).
