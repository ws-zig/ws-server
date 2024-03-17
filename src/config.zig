// Copyright 2024 Nick-Ilhan Atamgüc
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

const std = @import("std");

const Experimental = struct {
    /// Enables support for PerMessageDeflate.
    compression: bool = false,
};

pub const Config = struct {
    /// Specifies how large the buffer of bytes to be read should be.
    read_buffer_size: usize = 65535,
    /// Specifies how large a complete message can be.
    max_msg_size: usize = std.math.maxInt(u32),

    /// Experimental configurations should only be used for testing purposes.
    experimental: Experimental = .{},
};
