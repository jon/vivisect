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

"""Verilator Toolchain definition, rule, and Bzlmod module extension."""

VerilatorToolchainInfo = provider(
    doc = "Toolchain info containing Verilator binary path and runtime includes.",
    fields = {
        "verilator_path": "string: Path to verilator binary.",
        "include_dir": "string: Path to Verilator C++ runtime include headers.",
        "version": "string: Verilator version (e.g. 5.020).",
    },
)

def _verilator_toolchain_impl(ctx):
    info = VerilatorToolchainInfo(
        verilator_path = ctx.attr.verilator_path,
        include_dir = ctx.attr.include_dir,
        version = ctx.attr.version,
    )
    return [platform_common.ToolchainInfo(verilator = info)]

verilator_toolchain = rule(
    implementation = _verilator_toolchain_impl,
    attrs = {
        "verilator_path": attr.string(mandatory = True),
        "include_dir": attr.string(mandatory = True),
        "version": attr.string(default = ""),
    },
)

def _verilator_repo_impl(rctx):
    verilator_path = rctx.attr.path
    include_dir = rctx.attr.include_dir
    version = rctx.attr.version

    rctx.symlink(include_dir, "include")

    build_content = """package(default_visibility = ["//visibility:public"])

load("@rules_cc//cc:defs.bzl", "cc_library")
load("@vivisect//rules/toolchains:verilator.bzl", "verilator_toolchain")

cc_library(
    name = "runtime",
    hdrs = glob(["include/**/*.h", "include/**/*.c", "include/**/*.cpp"]),
    srcs = [
        "include/verilated.cpp",
        "include/verilated_dpi.cpp",
        "include/verilated_threads.cpp",
        "include/verilated_timing.cpp",
        "include/verilated_vcd_c.cpp",
    ],
    includes = ["include", "include/vltstd"],
    copts = ["-std=c++20"],
    linkopts = ["-pthread", "-latomic"],
)

verilator_toolchain(
    name = "verilator_toolchain_impl",
    verilator_path = "{verilator_path}",
    include_dir = "{include_dir}",
    version = "{version}",
)

toolchain(
    name = "toolchain",
    toolchain = ":verilator_toolchain_impl",
    toolchain_type = "@vivisect//rules/toolchains:verilator_toolchain_type",
)
""".format(
        verilator_path = verilator_path,
        include_dir = include_dir,
        version = version,
    )

    rctx.file("BUILD.bazel", build_content)

_verilator_repo = repository_rule(
    implementation = _verilator_repo_impl,
    attrs = {
        "path": attr.string(mandatory = True),
        "include_dir": attr.string(mandatory = True),
        "version": attr.string(default = ""),
    },
)

_toolchain_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "path": attr.string(mandatory = True),
        "include_dir": attr.string(mandatory = True),
        "version": attr.string(default = ""),
    },
)

def _verilator_extension_impl(module_ctx):
    for mod in module_ctx.modules:
        for t in mod.tags.toolchain:
            _verilator_repo(
                name = t.name,
                path = t.path,
                include_dir = t.include_dir,
                version = t.version,
            )

verilator = module_extension(
    implementation = _verilator_extension_impl,
    tag_classes = {
        "toolchain": _toolchain_tag,
    },
)
