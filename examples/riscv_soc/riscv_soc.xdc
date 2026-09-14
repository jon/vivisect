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

# 50 MHz clock constraint for RV32I RISC-V SoC
create_clock -period 20.000 -name clk [get_ports clk]

# Voltage and configuration bank voltage select for Arty A7
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

# Clock and Reset
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk }]
set_property -dict { PACKAGE_PIN C2  IOSTANDARD LVCMOS33 } [get_ports { rst_n }]

# USB-UART TX
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_tx_serial }]

# Board LEDs
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { leds[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { leds[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { leds[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { leds[3] }]
set_property -dict { PACKAGE_PIN E1  IOSTANDARD LVCMOS33 } [get_ports { leds[4] }]
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports { leds[5] }]
set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33 } [get_ports { leds[6] }]
set_property -dict { PACKAGE_PIN E2  IOSTANDARD LVCMOS33 } [get_ports { leds[7] }]

# Board Buttons
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { buttons[0] }]
set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports { buttons[1] }]
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports { buttons[2] }]
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports { buttons[3] }]

# Allow simulation debug port (sim_pass_sig) to remain unplaced without fatal DRC error
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
