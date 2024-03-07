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
const SourceLocation = std.builtin.SourceLocation;

pub const Error = struct {
    _error: anyerror,
    _location: SourceLocation,

    const Self = @This();

    pub inline fn getError(self: *const Self) anyerror {
        return self._error;
    }

    pub inline fn getLocation(self: *const Self) SourceLocation {
        return self._location;
    }

    pub inline fn getFile(self: *const Self) [:0]const u8 {
        return self._location.file;
    }

    pub inline fn getFnName(self: *const Self) [:0]const u8 {
        return self._location.fn_name;
    }

    pub inline fn getLine(self: *const Self) u32 {
        return self._location.line;
    }

    pub inline fn getColumn(self: *const Self) u32 {
        return self._location.column;
    }
};
