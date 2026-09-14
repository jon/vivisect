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

"""AMD / Xilinx FPGA part definition rule and provider."""

load("//rules:providers.bzl", "VivadoPartInfo")

def _parse_part_string(part_str):
    """Parses standard Xilinx part strings (e.g. xc7a100tcsg324-1)."""
    speed = ""
    rest = part_str
    if "-" in part_str:
        rest, speed_part = part_str.rsplit("-", 1)
        speed = "-" + speed_part

    # Identify family prefix
    family = "unknown"
    if rest.startswith("xc7a"):
        family = "artix7"
    elif rest.startswith("xc7k"):
        family = "kintex7"
    elif rest.startswith("xc7v"):
        family = "virtex7"
    elif rest.startswith("xc7z"):
        family = "zynq7000"
    elif rest.startswith("xcku"):
        family = "kintexu"
    elif rest.startswith("xcvu"):
        family = "virtexu"
    elif rest.startswith("xczu"):
        family = "zynquplus"

    return family, rest, speed

def _vivado_part_impl(ctx):
    part_name = ctx.attr.part if ctx.attr.part else ctx.label.name
    family, default_device, default_speed = _parse_part_string(part_name)

    family_val = ctx.attr.family if ctx.attr.family else family
    device_val = ctx.attr.device if ctx.attr.device else default_device
    package_val = ctx.attr.package if ctx.attr.package else ""
    speed_val = ctx.attr.speed if ctx.attr.speed else default_speed

    part_info = VivadoPartInfo(
        part = part_name,
        family = family_val,
        device = device_val,
        package = package_val,
        speed = speed_val,
    )

    return [
        DefaultInfo(),
        part_info,
    ]

vivado_part = rule(
    implementation = _vivado_part_impl,
    doc = "Defines a canonical AMD/Xilinx FPGA silicon part specification.",
    attrs = {
        "part": attr.string(
            default = "",
            doc = "Canonical part string (<device><package><speed_grade>). Defaults to rule name.",
        ),
        "family": attr.string(
            default = "",
            doc = "FPGA architecture family (e.g. 'artix7', 'kintexuplus').",
        ),
        "device": attr.string(
            default = "",
            doc = "FPGA silicon device identifier (e.g. 'xc7a100t').",
        ),
        "package": attr.string(
            default = "",
            doc = "FPGA silicon package identifier (e.g. 'csg324').",
        ),
        "speed": attr.string(
            default = "",
            doc = "FPGA silicon speed grade (e.g. '-1').",
        ),
    },
)
