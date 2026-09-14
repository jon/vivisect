// Copyright 2026 The Vivisect Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`timescale 1ns / 1ps

package base_pkg;
  typedef enum logic [1:0] {
    STATUS_IDLE = 2'b00,
    STATUS_BUSY = 2'b01,
    STATUS_OK   = 2'b10,
    STATUS_ERR  = 2'b11
  } status_e;

  typedef logic [7:0] node_id_t;
endpackage
