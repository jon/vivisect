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

# Clock constraints for CDC FIFO
create_clock -period 10.000 -name wclk [get_ports wclk]
create_clock -period 15.000 -name rclk [get_ports rclk]

# Asynchronous clock domains
set_clock_groups -asynchronous -group [get_clocks wclk] -group [get_clocks rclk]

# Bounded datapath delay for CDC Gray pointer crossings
set_max_delay 10.0 -datapath_only -from [get_cells -hier -filter {NAME =~ *wgray_reg*}] -to [get_cells -hier -filter {NAME =~ *u_sync_w2r*sync_stage1_reg*}]
set_max_delay 15.0 -datapath_only -from [get_cells -hier -filter {NAME =~ *rgray_reg*}] -to [get_cells -hier -filter {NAME =~ *u_sync_r2w*sync_stage1_reg*}]
