# Vivisect

Bazel rules for AMD FPGA development and hardware simulation, integrating
AMD Vivado (`xvlog`, `xelab`, `xsim`, `vivado`) and Verilator with modern
Bazel (Bzlmod).

## Overview

Hardware development workflows frequently suffer from monolithic,
non-incremental scripts and invasive tool behavior. Vivisect bridges AMD
FPGA tooling and Verilator into Bazel:

- **Isolated Execution**: Strict per-action scratch directories eliminate
  EDA file spew (`.Xil/`, `*.log`, `*.jou`, `*.pb`) in workspace
  directories.
- **Incremental Multi-Stage Caching**: Decomposes synthesis, placement &
  routing, and bitstream generation into cached Design Checkpoint (`.dcp`)
  stages.
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

Verify workspace configuration:
```bash
bazel build //...
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

## Repository Layout

```
├── MODULE.bazel                 # Bzlmod module definition & toolchains
├── .bazelrc                     # Build configurations & licensing flags
├── AGENTS.md                    # Agent guidelines & commit gates
├── BUILD.bazel                  # Root package declaration & style sources
├── LICENSE                      # Apache License, Version 2.0
├── NOTICE                       # Copyright attribution & third-party notices
└── README.md                    # Workspace overview and documentation
```

## Contributing & Agent Guidelines

See [AGENTS.md](AGENTS.md) for commit message specifications (classic Git /
Linux kernel style with Markdown permitted), commit gates, formatting
standards, and execution requirements.

## License

Vivisect is licensed under the [Apache License, Version 2.0](LICENSE).

Copyright 2026 The Vivisect Authors.

For third-party attributions and notices, see [NOTICE](NOTICE).
