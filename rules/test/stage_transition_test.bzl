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

"""Starlark analysis tests for target-stage transitions and select()."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//rules:providers.bzl", "SvInfo")
load(
    "//rules:stage.bzl",
    "simulation_transition",
    "synthesis_transition",
    "verilator_transition",
)

def _transition_inspector_impl(ctx):
    dep = ctx.attr.dep[0] if type(ctx.attr.dep) == "list" else ctx.attr.dep
    sv_info = dep[SvInfo]
    return [
        DefaultInfo(files = sv_info.srcs),
        sv_info,
    ]

synth_inspector = rule(
    implementation = _transition_inspector_impl,
    attrs = {
        "dep": attr.label(
            providers = [SvInfo],
            cfg = synthesis_transition,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

sim_inspector = rule(
    implementation = _transition_inspector_impl,
    attrs = {
        "dep": attr.label(
            providers = [SvInfo],
            cfg = simulation_transition,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

verilator_inspector = rule(
    implementation = _transition_inspector_impl,
    attrs = {
        "dep": attr.label(
            providers = [SvInfo],
            cfg = verilator_transition,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def _synth_stage_test_impl(ctx):
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)
    sv_info = tut[SvInfo]
    src_basenames = [s.basename for s in sv_info.srcs.to_list()]
    asserts.equals(env, ["synth_impl.sv"], src_basenames)
    return analysistest.end(env)

synth_stage_test = analysistest.make(_synth_stage_test_impl)

def _sim_stage_test_impl(ctx):
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)
    sv_info = tut[SvInfo]
    src_basenames = [s.basename for s in sv_info.srcs.to_list()]
    asserts.equals(env, ["sim_impl.sv"], src_basenames)
    return analysistest.end(env)

sim_stage_test = analysistest.make(_sim_stage_test_impl)

def _verilator_stage_test_impl(ctx):
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)
    sv_info = tut[SvInfo]
    src_basenames = [s.basename for s in sv_info.srcs.to_list()]
    asserts.equals(env, ["verilator_impl.sv"], src_basenames)
    return analysistest.end(env)

verilator_stage_test = analysistest.make(_verilator_stage_test_impl)
