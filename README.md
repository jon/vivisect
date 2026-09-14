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
- **Hierarchical Out-of-Context Stitching**: Compose multi-tier FPGA
  designs via `cells = {"u_inst": ":cell_synth"}` with automated stub
  generation and in-memory netlist stitching.
- **Machine-Readable Utilization Gates**: Enforce strict FPGA resource
  budgets (LUTs, registers, BRAM, DSP) via `vivado_utilization_test` in
  milliseconds without launching Vivado.
- **Target-Stage Transitions (`select()` support)**: Automatic incoming
  transitions allow SystemVerilog code to select between synthesis stubs,
  simulation netlists, and Verilator models without CLI flags or cache churn.
- **Hardware Abstraction**: Canonical silicon parts (`vivado_part`),
  development boards (`vivado_board`), and constraint categorization
  (`xdc_library`).
- **IP Catalog Codegen**: Configure and generate vendor IP cores
  (`vivado_ip`) with black-box stubs for synthesis and functional netlists
  for simulation.
- **Fast Simulation & Linting**: Co-locates rapid Verilator lint checks
  and C++ simulations alongside standard Vivado `xsim` regressions.
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

## Hardware Definitions & Constraints

### `vivado_part`
Declares canonical silicon part strings (`<device><package><speed_grade>`):

```starlark
load("//rules:defs.bzl", "vivado_part")

vivado_part(
    name = "xc7a100tcsg324-1",
    device = "xc7a100t",
    family = "artix7",
    package = "csg324",
    speed = "-1",
)
```

### `xdc_library`
Manages physical and timing design constraints categorized by stage and
scoping:

```starlark
load("//rules:defs.bzl", "xdc_library")

xdc_library(
    name = "pinout_constraints",
    srcs = ["constraints/pins.xdc"],
    used_in = ["synth", "impl"],
)
```

### `vivado_board`
Binds an FPGA part to a master constraint library and optional AMD board part
identifier:

```starlark
load("//rules:defs.bzl", "vivado_board")

vivado_board(
    name = "arty_a7_100",
    board_part = "digilentinc.com:arty-a7-100:part0:1.1",
    constraints = [":master_xdc"],
    part = "//parts:xc7a100tcsg324-1",
)
```

---

## FPGA Build Pipeline

Vivisect decomposes FPGA synthesis and implementation into composable,
incremental targets:

### `vivado_synth`
Synthesizes SystemVerilog/Verilog designs using AMD Vivado:
- **Top-Level Parameters (`parameters`)**: Dictionary mapping top-level module
  parameter names to values (passed as `-generic` to `synth_design`),
  enabling parameterized out-of-context checkpoint and stub generation.
- **Out-of-Context (OOC)**: Set `out_of_context = True` to disable I/O buffer
  insertion and automatically generate a black-box Verilog stub
  (`<name>_stub.v`).
- **Hermetic Stubs**: Automatically sanitizes generated black-box stubs by
  stripping execution timestamps (`// Date`), hostnames (`// Host`), and
  scratch paths (`// Command`) to guarantee byte-for-byte reproducibility
  across builds.
- **Hierarchical Cell Linking (`cells`)**: Stitch child out-of-context
  checkpoints into a parent netlist using `cells = {"u_instance":
  ":child_ooc"}`. Synthesis runs in two stages: synthesizes parent with child
  stubs, then links checkpoints in an in-memory project.
- **Strict Source Ordering**: Linearizes all transitive dependencies into
  `packages -> interfaces -> modules` ahead of direct sources, ensuring
  Vivado's `read_verilog -sv` encounters package declarations before module
  consumers even if dependencies are listed out of order.

### `vivado_impl`
Executes physical implementation through design checkpoints:
- **Incremental Stages**: Runs `opt_design`, `place_design`, `phys_opt_design`,
  and `route_design` in succession.
- **Reports**: Exports routability metrics, design rule check (DRC) reports,
  utilization summaries, and static timing analyses.

### `vivado_bitstream`
Generates binary configuration bitstreams (`.bit`) and flash memory files
(`.bin`) from routed checkpoints. Supports pre-bitstream Tcl hooks:

```starlark
vivado_bitstream(
    name = "soc_bitstream",
    impl = ":soc_impl",
    tcl_hooks = ["bitstream_pre.tcl"],
)
```

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
├── parts/                       # Canonical silicon part definitions
├── rules/
│   ├── defs.bzl                 # Public API entrypoint
│   ├── providers.bzl            # Hardware Starlark providers
│   ├── stage.bzl                # Stage transitions & build setting
│   ├── support/                 # run_isolated.py runner and unit tests
│   ├── sv/                      # sv_library, verilator rules & tests
│   ├── test/                    # providers_test and style_test
│   ├── toolchains/              # Vivado and Verilator toolchains
│   └── xilinx/                  # FPGA synthesis, impl, bitstream & xsim
└── examples/
    ├── counter/                 # Parameterized counter RTL & dual-sim tests
    └── ip_core/                 # Vivado IP Catalog core generation example
```

## Contributing & Agent Guidelines

See [AGENTS.md](AGENTS.md) for commit message specifications (classic Git /
Linux kernel style with Markdown permitted), commit gates, formatting
standards, and execution requirements.

## License

Vivisect is licensed under the [Apache License, Version 2.0](LICENSE).

Copyright 2026 The Vivisect Authors.

For third-party attributions and notices, see [NOTICE](NOTICE).
