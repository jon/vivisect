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

"""Vivado Toolchain definition, rule, and Bzlmod module extension."""

VivadoToolchainInfo = provider(
    doc = "Toolchain info containing AMD Vivado binary paths, runner, and simulation support files.",
    fields = {
        "vivado_path": "string: Path to vivado executable.",
        "xvlog_path": "string: Path to xvlog executable.",
        "xelab_path": "string: Path to xelab executable.",
        "xsim_path": "string: Path to xsim executable.",
        "version": "string: Vivado version (e.g. 2026.1).",
        "isolated_runner": "File: The run_isolated.py wrapper script.",
        "glbl_src": "File: The glbl.v source file artifact.",
        "glbl_path": "string: Path to glbl.v source file.",
    },
)

def _vivado_toolchain_impl(ctx):
    info = VivadoToolchainInfo(
        vivado_path = ctx.attr.vivado_path,
        xvlog_path = ctx.attr.xvlog_path,
        xelab_path = ctx.attr.xelab_path,
        xsim_path = ctx.attr.xsim_path,
        version = ctx.attr.version,
        isolated_runner = ctx.file.isolated_runner,
        glbl_src = ctx.file.glbl_src,
        glbl_path = ctx.file.glbl_src.path if ctx.file.glbl_src else "",
    )
    return [platform_common.ToolchainInfo(vivado = info)]

vivado_toolchain = rule(
    implementation = _vivado_toolchain_impl,
    attrs = {
        "vivado_path": attr.string(mandatory = True),
        "xvlog_path": attr.string(mandatory = True),
        "xelab_path": attr.string(mandatory = True),
        "xsim_path": attr.string(mandatory = True),
        "version": attr.string(default = ""),
        "isolated_runner": attr.label(
            default = Label("//rules/support:run_isolated.py"),
            allow_single_file = True,
        ),
        "glbl_src": attr.label(
            allow_single_file = True,
        ),
    },
)

def _vivado_repo_impl(rctx):
    install_path = rctx.attr.install_path
    version = rctx.attr.version

    vivado_bin = install_path + "/bin/vivado"
    xvlog_bin = install_path + "/bin/xvlog"
    xelab_bin = install_path + "/bin/xelab"
    xsim_bin = install_path + "/bin/xsim"

    glbl_candidates = [
        install_path + "/data/verilog/src/glbl.v",
        install_path + "/../data/verilog/src/glbl.v",
        install_path + "/ids_lite/ISE/verilog/src/glbl.v",
    ]
    glbl_found = None
    for cand in glbl_candidates:
        p = rctx.path(cand)
        if p.exists:
            glbl_found = p
            break

    glbl_filegroup = ""
    glbl_attr = ""
    if glbl_found:
        rctx.symlink(glbl_found, "glbl.v")
        glbl_filegroup = """exports_files(["glbl.v"])

filegroup(
    name = "glbl",
    srcs = ["glbl.v"],
)
"""
        glbl_attr = '    glbl_src = ":glbl.v",\n'

    build_content = """package(default_visibility = ["//visibility:public"])

load("@vivisect//rules/toolchains:vivado.bzl", "vivado_toolchain")

{glbl_filegroup}
vivado_toolchain(
    name = "vivado_toolchain_impl",
    vivado_path = "{vivado_bin}",
    xvlog_path = "{xvlog_bin}",
    xelab_path = "{xelab_bin}",
    xsim_path = "{xsim_bin}",
    version = "{version}",
    isolated_runner = "@vivisect//rules/support:run_isolated.py",
{glbl_attr})

toolchain(
    name = "toolchain",
    toolchain = ":vivado_toolchain_impl",
    toolchain_type = "@vivisect//rules/toolchains:vivado_toolchain_type",
)
""".format(
        glbl_filegroup = glbl_filegroup,
        glbl_attr = glbl_attr,
        vivado_bin = vivado_bin,
        xvlog_bin = xvlog_bin,
        xelab_bin = xelab_bin,
        xsim_bin = xsim_bin,
        version = version,
    )

    rctx.file("BUILD.bazel", build_content)

_vivado_repo = repository_rule(
    implementation = _vivado_repo_impl,
    attrs = {
        "install_path": attr.string(mandatory = True),
        "version": attr.string(default = ""),
    },
)

_toolchain_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "install_path": attr.string(mandatory = True),
        "version": attr.string(default = ""),
    },
)

def _vivado_extension_impl(module_ctx):
    for mod in module_ctx.modules:
        for t in mod.tags.toolchain:
            _vivado_repo(
                name = t.name,
                install_path = t.install_path,
                version = t.version,
            )

vivado = module_extension(
    implementation = _vivado_extension_impl,
    tag_classes = {
        "toolchain": _toolchain_tag,
    },
)
