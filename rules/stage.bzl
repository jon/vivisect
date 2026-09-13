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

"""Build settings and transitions for vivisect target-stage selection."""

def _verilator_transition_impl(settings, attr):
    return {"//rules:stage": "verilator"}

verilator_transition = transition(
    implementation = _verilator_transition_impl,
    inputs = [],
    outputs = ["//rules:stage"],
)

def _simulation_transition_impl(settings, attr):
    return {"//rules:stage": "simulation"}

simulation_transition = transition(
    implementation = _simulation_transition_impl,
    inputs = [],
    outputs = ["//rules:stage"],
)

def _synthesis_transition_impl(settings, attr):
    return {"//rules:stage": "synthesis"}

synthesis_transition = transition(
    implementation = _synthesis_transition_impl,
    inputs = [],
    outputs = ["//rules:stage"],
)
