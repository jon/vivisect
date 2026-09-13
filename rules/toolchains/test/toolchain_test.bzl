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

"""Unit tests for vivisect Vivado and Verilator toolchain resolution."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

VIVADO_TOOLCHAIN_TYPE = Label("//rules/toolchains:vivado_toolchain_type")
VERILATOR_TOOLCHAIN_TYPE = Label("//rules/toolchains:verilator_toolchain_type")

def _toolchain_test_impl(ctx):
    env = unittest.begin(ctx)

    # Check Vivado toolchain resolution
    vivado_toolchain = ctx.toolchains[VIVADO_TOOLCHAIN_TYPE]
    asserts.true(env, vivado_toolchain != None, "Vivado toolchain must be resolved")
    vivado_info = vivado_toolchain.vivado
    asserts.true(env, vivado_info != None, "VivadoToolchainInfo must be present")
    asserts.true(
        env,
        vivado_info.vivado_path.endswith("/bin/vivado"),
        "vivado_path must end with /bin/vivado",
    )
    asserts.true(
        env,
        vivado_info.xvlog_path.endswith("/bin/xvlog"),
        "xvlog_path must end with /bin/xvlog",
    )
    asserts.true(
        env,
        vivado_info.xelab_path.endswith("/bin/xelab"),
        "xelab_path must end with /bin/xelab",
    )
    asserts.true(
        env,
        vivado_info.xsim_path.endswith("/bin/xsim"),
        "xsim_path must end with /bin/xsim",
    )
    asserts.equals(env, "2026.1", vivado_info.version)
    asserts.true(env, vivado_info.glbl_src != None, "glbl_src must be resolved")
    asserts.true(
        env,
        vivado_info.glbl_path.endswith("glbl.v"),
        "glbl_path must end with glbl.v",
    )

    # Check Verilator toolchain resolution
    verilator_toolchain = ctx.toolchains[VERILATOR_TOOLCHAIN_TYPE]
    asserts.true(env, verilator_toolchain != None, "Verilator toolchain must be resolved")
    verilator_info = verilator_toolchain.verilator
    asserts.true(env, verilator_info != None, "VerilatorToolchainInfo must be present")
    asserts.equals(env, "/usr/bin/verilator", verilator_info.verilator_path)
    asserts.equals(env, "/usr/share/verilator/include", verilator_info.include_dir)
    asserts.equals(env, "5.020", verilator_info.version)

    return unittest.end(env)

toolchain_test = unittest.make(
    _toolchain_test_impl,
    toolchains = [
        VIVADO_TOOLCHAIN_TYPE,
        VERILATOR_TOOLCHAIN_TYPE,
    ],
)

def toolchain_test_suite(name):
    unittest.suite(
        name,
        toolchain_test,
    )
