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
const Allocator = std.mem.Allocator;

const Frame = @import("./frame.zig").Frame;

pub const Type = enum(u8) {
    Unknown = 255,
    Continue = 0,
    Text = 1,
    Binary = 2,
    Close = 8,
    Ping = 9,
    Pong = 10,

    const Self = @This();

    pub fn from(opcode: u8) Type {
        return switch (opcode) {
            0 => Type.Continue,
            1 => Type.Text,
            2 => Type.Binary,
            8 => Type.Close,
            9 => Type.Ping,
            10 => Type.Pong,
            else => Type.Unknown,
        };
    }

    pub fn into(self: Self) u8 {
        const opcode = @intFromEnum(self);
        return opcode;
    }
};

pub const Message = struct {
    allocator: *const Allocator = undefined,
    _bytes: ?[]u8 = null,
    // Tells us whether the message is complete or whether we need to wait for new data.
    _ready: bool = false,
    _type: Type = Type.Unknown,

    const Self = @This();

    pub fn get(self: *Self) *?[]u8 {
        return &self._bytes;
    }

    pub fn isReady(self: *Self) bool {
        return self._ready;
    }

    pub fn getType(self: *Self) Type {
        return self._type;
    }

    /// This function is used to read a frame. If do you need the data, use `get()`.
    pub fn read(self: *Self, buffer: []const u8) anyerror!void {
        if (self.allocator == undefined) {
            return error.Message_MissingAllocator;
        }

        var frame = Frame{ .allocator = self.allocator, .bytes = buffer };
        defer frame.deinit();

        const data = try frame.read();

        self._ready = frame.getFin();
        self._type = Type.from(frame.getOpcode());

        var old_bytes_len: usize = 0;
        if (self._bytes == null) {
            self._bytes = try self.allocator.alloc(u8, data.len);
        } else {
            old_bytes_len = self._bytes.?.len;
            self._bytes = try self.allocator.realloc(self._bytes.?, old_bytes_len + data.len);
        }

        @memcpy(self._bytes.?[old_bytes_len..], data.*);
    }

    fn _write(self: *Self, data: []const u8) anyerror!void {
        if (self.allocator == undefined) {
            return error.Message_MissingAllocator;
        }

        var frame = Frame{ .allocator = self.allocator, .bytes = data };
        defer frame.deinit();
        const frame_bytes = try frame.write(self._type.into());
        self._bytes = try self.allocator.alloc(u8, frame_bytes.*.len);
        @memcpy(self._bytes.?, frame_bytes.*);
    }

    pub fn writeText(self: *Self, data: []const u8) anyerror!void {
        self._type = Type.Text;
        try self._write(data);
    }

    pub fn writeClose(self: *Self) anyerror!void {
        self._type = Type.Close;
        try self._write("");
    }

    pub fn writePing(self: *Self) anyerror!void {
        self._type = Type.Ping;
        try self._write("");
    }

    pub fn writePong(self: *Self) anyerror!void {
        self._type = Type.Pong;
        try self._write("");
    }

    pub fn deinit(self: *Self) void {
        if (self._bytes != null) {
            self.allocator.free(self._bytes.?);
        }
        self.* = undefined;
    }
};
