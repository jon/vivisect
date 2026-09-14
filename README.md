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

## Prerequisites

- **Bazelisk**: Recommended Bazel launcher (fetches Bazel 9+ via Bzlmod).
- **AMD Vivado / Vitis**: Tested with Vivado 2025.2 and 2026.1 installed at
  `/tools/Xilinx` (or custom `$XILINX_VIVADO`).
- **Verilator**: Verilator 5.0+ (`/usr/bin/verilator`).
- **Host C++ Toolchain**: GCC/Clang with standard build utilities (`make`,
  `g++`).

## Quickstart

Verify your workspace installation and run the test suite:

```bash
bazel info release
bazel build //...
bazel test //...
```

### Execution Profiles

Vivisect supports two execution modes out-of-the-box via `.bazelrc`:

1. **Sandboxed EDA (Default)**:
   Mounts host tool directories (e.g. `/tools/Xilinx`) directly into Bazel's
   Linux sandbox:
   ```bash
   bazel build --config=sandboxed_eda //...
   ```

2. **Local EDA**:
   Executes EDA actions locally when strict sandbox mounting is not
   required or when troubleshooting license daemons:
   ```bash
   bazel build --config=local_eda //...
   ```

### Hardware Licensing

To point Vivado tools to your floating or node-locked license servers, export
`XILINXD_LICENSE_FILE` or `LM_LICENSE_FILE` in your host shell:

```bash
export XILINXD_LICENSE_FILE="2100@licenseserver.local"
# or for node-locked licenses in ~/.Xilinx:
export XILINXD_LICENSE_FILE="$HOME/.Xilinx/Xilinx.lic"
```

Bazel will automatically forward these variables to actions. For node-locked
licenses, the action runner (`run_isolated.py`) symlinks `.lic` files from
`$HOME/.Xilinx/` into the action's disposable home directory.

The runner suppresses compiler and tool `stdout`/`stderr` during successful
action execution, preserving full outputs in declared `.log` artifacts in
`bazel-bin/` while flushing captured diagnostics to `stderr` upon failure.
For interactive debugging, `--verbose` may be passed to stream process outputs
directly.

---

## Target-Stage Transitions & `select()`

Vivisect defines a stage build setting in `//rules:stage` (values:
`"synthesis"`, `"simulation"`, `"verilator"`). Config settings allow users to
select sources based on the active backend:
- `//rules:is_synthesis`
- `//rules:is_simulation` / `//rules:is_xsim`
- `//rules:is_verilator`

Rules automatically apply incoming edge transitions on `deps`:
- `vivado_synth` transitions dependencies to `stage = "synthesis"`.
- `xelab` and `xsim_test` transition dependencies to `stage = "simulation"`.
- `verilator_test` and `verilator_lint_test` transition dependencies to
  `stage = "verilator"`.

Users can write standard `select()` in `sv_library`:

```starlark
sv_library(
    name = "memory_controller",
    srcs = select({
        "//rules:is_synthesis": ["rtl/mem_controller.sv"],
        "//rules:is_verilator": ["sim/mem_model_cpp.sv"],
        "//conditions:default": ["sim/mem_model_behavioral.sv"],
    }),
)
```

Running `bazel test //...` evaluates Verilator tests, `xsim` regressions, and
synthesis runs concurrently in the same invocation without cache conflicts.

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
    constraints = ["//vendor/digilent/arty_a7_100:arty_a7_100_master"],
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
- **Utilization Reporting**: Generates `<name>_utilization.json` and
  human-readable `<name>_utilization.rpt`.

```starlark
load("//rules:defs.bzl", "vivado_synth")

vivado_synth(
    name = "top_synth",
    top = "top_system",
    deps = [":top_system_rtl"],
    cells = {
        "u_mid": ":mid_ooc",
    },
    board = "//boards/digilent/arty_a7_100:arty_a7_100",
    xdc = [":arty_pins"],
)
```

### `vivado_utilization_test`
Asserts absolute resource caps or percentage thresholds against
`<name>_utilization.json`:
- **Fast Execution**: Pure Python sandboxed test executing in milliseconds.
- **Resource Caps**: `max_luts`, `max_registers`, `max_bram`, `max_dsps`,
  `max_slices`.
- **Percentage Caps**: `max_lut_pct`, `max_register_pct`, `max_bram_pct`,
  `max_dsp_pct`.

```starlark
load("//rules:defs.bzl", "vivado_utilization_test")

vivado_utilization_test(
    name = "top_util_test",
    checkpoint = ":top_synth",
    max_luts = 500,
    max_registers = 500,
    max_lut_pct = "5.0",
)
```

### `vivado_ip`
Configures and synthesizes Vivado IP Catalog cores, generating design
checkpoints, hermetically sanitized black-box stubs, and simulation netlists:
- **`extra_inputs`**: External configuration and data files required during IP
  generation (such as Block RAM `.coe` memory initialization files or MIG
  `.prj` interface files). Files are staged into the isolated scratch
  directory and path references are automatically resolved in generated Tcl
  scripts.

```starlark
load("//rules:defs.bzl", "vivado_ip")

vivado_ip(
    name = "bram_rom_16x8",
    ip_name = "blk_mem_gen",
    module_name = "bram_rom_16x8",
    part = "//parts:xc7a100tcsg324-1",
    extra_inputs = ["rom_init.coe"],
    config = {
        "CONFIG.Memory_Type": "Single_Port_ROM",
        "CONFIG.Write_Width_A": "8",
        "CONFIG.Write_Depth_A": "16",
        "CONFIG.Read_Width_A": "8",
        "CONFIG.Load_Init_File": "true",
        "CONFIG.Coe_File": "rom_init.coe",
    },
)
```

### `vivado_impl`
Executes physical implementation (`opt_design`, `place_design`,
`phys_opt_design`, `route_design`):
- Emits fully routed checkpoint (`<name>.dcp`), timing summary
  (`<name>_timing_summary.rpt`), post-route utilization reports, and I/O
  reports.

```starlark
load("//rules:defs.bzl", "vivado_impl")

vivado_impl(
    name = "top_impl",
    checkpoint = ":top_synth",
    board = "//boards/digilent/arty_a7_100:arty_a7_100",
    xdc = [":arty_pins"],
)
```

### `vivado_timing_test`
Asserts static timing closure against post-implementation or post-synthesis
timing reports:
- **Fast Execution**: Pure Python sandboxed test parsing
  `<name>_timing_summary.rpt` in milliseconds without launching Vivado.
- **Timing Thresholds**: `min_wns` (Worst Negative Slack), `min_whs` (Worst
  Hold Slack), `max_tns` (Total Negative Slack), `max_ths` (Total Hold Slack).
- **Formatted Scorecard**: Emits formatted ASCII timing scoreboard detailing
  measured slack vs thresholds.

```starlark
load("//rules:defs.bzl", "vivado_timing_test")

vivado_timing_test(
    name = "top_timing_test",
    checkpoint = ":top_impl",
    min_wns = "0.0",
    min_whs = "0.0",
)
```

### `vivado_bitstream`
Generates FPGA programming bitstreams (`<name>.bit`) and optional SPI flash
binaries (`<name>.bin`):
- **`bin_file = True`**: Generates raw binary memory file for SPI flash
  programmer.
- **`tcl_hooks`**: List of Tcl scripts sourced after opening checkpoint and
  before `write_bitstream` (for configuring SPI bus width, bitstream
  compression, or DRC check severities).

```starlark
load("//rules:defs.bzl", "vivado_bitstream")

vivado_bitstream(
    name = "top_bitstream",
    checkpoint = ":top_impl",
    bin_file = True,
    tcl_hooks = ["bitstream_pre.tcl"],
)
```

---

## Starlark Providers

Vivisect defines hardware metadata providers in `//rules:providers.bzl`
(exported via `//rules:defs.bzl`):

- **`SvInfo`**: SystemVerilog/Verilog sources, headers (`.svh`, `.vh`),
  includes, defines, package/interface/module ordering, data files, and
  Verilator `.vlt` configuration/waiver files.
- **`VivadoPartInfo`**: Canonical silicon part specification (`part`,
  `family`, `device`, `package`, `speed`).
- **`VivadoBoardInfo`**: Development board specification (`part_info`, `part`,
  `board_part`, `constraints`).
- **`VivadoConstraintsInfo`**: Design constraints categorized into
  `synth_constraints`, `impl_constraints`, and `scoped_constraints`.
- **`VivadoDcpInfo`**: Design Checkpoint (`.dcp`), top module, design stage,
  reports map (`utilization_json`, `timing`), stub, and stitched `cells`.
- **`XsimSnapshotInfo`**: Elaborated simulation snapshot directory
  (`xsim.dir/<snapshot>`) generated by `xelab`.
- **`VerilatorCppInfo`**: C++ header and source files produced by Verilator
  transpilation.
- **`TclInfo`**: Tcl automation scripts and initialization data files.

---

## SystemVerilog & Verilator Rules

### `sv_package`
Declares a pure SystemVerilog package library (`package ... endpackage`):
- **`srcs`**: Automatically classified as packages in `SvInfo.pkgs`.
- **Strict Precedence**: Guarantees all transitive package files are ordered
  ahead of interfaces and modules in compilation streams (`transitive_srcs`).
- **Standalone Linting**: Supports isolated linting via
  `verilator_lint_test(target_type = "package")`.

### `sv_interface`
Declares a SystemVerilog interface library (`interface ... endinterface`)
with signals, parameters, and modports:
- **`srcs`**: Automatically classified as interfaces in `SvInfo.interfaces`.
- **Strict Ordering**: Compiles after transitive packages and before downstream
  modules.
- **Standalone Linting**: Supports isolated linting via
  `verilator_lint_test(target_type = "interface")`.

### `sv_library`
Declares a SystemVerilog library propagating sources, interfaces, packages,
headers, includes, and defines:
- **`pkgs`**: SV package files compiled prior to interfaces and modules with
  topological ordering.
- **`interfaces`**: SV interface files compiled after packages and before
  modules.
- **`srcs`**: SV module/source files compiled after all transitive packages
  and interfaces.
- **`hdrs`**: Header files (`.svh`, `.vh`) tracked for caching.
- **`waivers`**: Verilator `.vlt` configuration and waiver files propagated
  transitively via `SvInfo`. `.vlt` files specified in `srcs` are also
  automatically partitioned into `waivers`.
- **`include_hdrs_dirs`**: Automatically derives `-I` / `-i` directories from
  header paths.

### `verilator_lint_test`
Performs static lint checks using `verilator --lint-only -Wall`:
- **`target_type`**: `"module"` (default), `"package"`, or `"interface"`.
  - `"package"`: Generates a synthetic top module `_vivisect_pkg_lint_top`
    importing `<top>::*` with `-Wno-UNUSEDPARAM`, validating package syntax,
    enums, structs, and functions without unused parameter errors.
  - `"interface"`: Generates a synthetic top module `_vivisect_if_lint_top`
    instantiating `<top> _if_inst()` with waivers for unused signals and
    missing pin bindings, validating interface syntax, modports, and port
    directions in complete isolation.
  - `"module"`: Standard module linting against `--top-module <top>`.
- **`top`**: Top-level module, package, or interface name to lint (defaults to
  the first dependency name if omitted).
- **`parameters`**: Dictionary of parameter overrides passed to synthetic
  interface stubs (`target_type = "interface"`), enabling standalone linting
  of parameterized interfaces without default values.
- **`waivers`**: Verilator `.vlt` configuration and waiver files (in addition
  to transitive waivers from `deps`).

### `verilator_library`
Transpiles SystemVerilog designs into reusable C++ model libraries
(`cc_library`) using Verilator `--cc`:
- Exposes generated C++ model headers (`V<top>.h`) and runtime classes.
- **Strict Source Ordering**: Passes transitive dependencies to Verilator in
  canonical `packages -> interfaces -> modules` order ahead of direct sources,
  ensuring package declarations precede module consumers regardless of
  dependency declaration order.
- **`waivers`**: Verilator `.vlt` configuration and waiver files passed to the
  transpiler (in addition to transitive waivers from `deps`).
- Enables arbitrary `cc_test`, `cc_binary`, or software co-simulation harnesses
  to instantiate and drive Verilated models.

### `verilator_test`
Builds a native simulation test using Verilator and `rules_cc`, supporting two
testing modes:
- **`waivers`**: Verilator `.vlt` configuration and waiver files forwarded to
  the underlying `verilator_library`.
- **Pure SystemVerilog Testbench (`tb = None`)**: When `tb` is omitted,
  simulates the top-level SystemVerilog testbench module directly using
  Verilator 5's `--timing` engine and auto-generated `main()` event loop.
  This matches the target contract of `xsim_test`, allowing the exact same
  testbench library to run across both simulators.
- **C++ Testbench (`tb = "my_tb.cpp"`)**: Transpiles the DUT into C++ and
  compiles `tb` as the test executable driver.

---

## AMD Simulation & Elaboration Rules

### `xsim_test`
Executes elaborated simulation snapshots under `xsim` with native multi-line
error trapping.
- **`waveforms = True`**: Automatically captures signals and exports
  `<name>.wdb`.
- **`libs = ["unisims_ver"]`**: UNISIM library dependencies automatically
  enable `glbl` elaboration and bind `glbl.v` from the toolchain.

### `xelab`
Elaborates SystemVerilog/Verilog sources into an `xsim.dir/<snapshot>` artifact.
- **`libs`**: Simulation libraries passed to `-L` (e.g. `["unisims_ver"]`).
- **Standard `glbl.v` support**: When `"unisims_ver"` is specified in `libs`
  or `"glbl"` is in `tops`, `xelab` automatically appends `-top glbl` and
  compiles Vivado's standard `glbl.v` (resolved from the Vivado toolchain) via
  `-svlog`, unless user sources already define `glbl.v`.

### `xvlog`
Compiles SystemVerilog/Verilog sources into an xsim library.
- **`glbl = True`**: Automatically includes and compiles Vivado's standard
  `glbl.v` into the generated library.

---

## Repository Layout

```
├── MODULE.bazel                 # Bzlmod module definition & toolchains
├── .bazelrc                     # Build configurations & licensing flags
├── AGENTS.md                    # Agent guidelines & commit gates
├── BUILD.bazel                  # Root package declaration & style sources
├── LICENSE                      # Apache License, Version 2.0
├── NOTICE                       # Copyright attribution & third-party notices
├── parts/                       # Canonical silicon part definitions
├── boards/                      # Development board definitions
├── vendor/                      # Third-party upstream board constraints
├── rules/
│   ├── defs.bzl                 # Public API entrypoint
│   ├── providers.bzl            # Hardware Starlark providers
│   ├── stage.bzl                # Stage transitions & build setting
│   ├── support/                 # run_isolated.py runner and unit tests
│   ├── sv/                      # sv_library, verilator rules & tests
│   ├── toolchains/              # Vivado and Verilator toolchains
│   └── xilinx/                  # FPGA synthesis, impl, bitstream & xsim
└── examples/
    ├── axi_stream_pipeline/     # 150MHz AXI4-Stream skid buffer & filter
    ├── cdc_fifo/                # Asynchronous dual-clock CDC FIFO
    ├── counter/                 # Parameterized counter RTL & dual-sim tests
    ├── hierarchical_counter/    # Multi-tier OOC synthesis, impl, bitstream
    ├── ip_core/                 # Vivado IP Catalog core generation example
    ├── ip_subsystem/            # Vendor IP integration with unisim glbl
    └── riscv_soc/               # RV32I RISC-V SoC with firmware & bitstream
```

## Contributing & Agent Guidelines

See [AGENTS.md](AGENTS.md) for commit message specifications (classic Git /
Linux kernel style with Markdown permitted), commit gates, formatting
standards, and execution requirements.

## License

Vivisect is licensed under the [Apache License, Version 2.0](LICENSE).

Copyright 2026 The Vivisect Authors.

For third-party attributions and notices, see [NOTICE](NOTICE).
