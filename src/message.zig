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
    Continue = 0,
    Text = 1,
    Binary = 2,
    Close = 8,
    Ping = 9,
    Pong = 10,

    const Self = @This();

    pub fn from(opcode: u8) anyerror!Self {
        return switch (opcode) {
            0 => Type.Continue,
            1 => Type.Text,
            2 => Type.Binary,
            8 => Type.Close,
            9 => Type.Ping,
            10 => Type.Pong,
            else => error.MessageType_Unknown,
        };
    }

    pub inline fn into(self: Self) u8 {
        return @intFromEnum(self);
    }
};

pub const Message = struct {
    allocator: *const Allocator,
    _bytes: ?[]u8 = null,
    // Tells us whether the message is complete or whether we need to wait for new data.
    _lastMessage: bool = false,
    _type: ?Type = null,

    const Self = @This();

    pub inline fn get(self: *const Self) ?[]u8 {
        return self._bytes;
    }

    pub inline fn isLastMessage(self: *const Self) bool {
        return self._lastMessage;
    }

    pub inline fn setLastMessage(self: *Self, value: bool) void {
        self._lastMessage = value;
    }

    pub inline fn getType(self: *const Self) ?Type {
        return self._type;
    }

    pub inline fn setType(self: *Self, comptime value: Type) void {
        self._type = value;
    }

    pub fn read(self: *Self, buffer: []const u8) anyerror!void {
        var frame: Frame = .{ .allocator = self.allocator, .bytes = buffer };
        defer frame.deinit();

        const data: ?[]u8 = try frame.read();

        self._lastMessage = frame.isLastFrame();
        if (self._type == null) {
            self._type = try Type.from(frame.getOpcode());
        }

        if (data) |data_result| {
            var old_bytes_len: usize = 0;
            if (self._bytes == null) {
                self._bytes = try self.allocator.alloc(u8, data_result.len);
            } else {
                old_bytes_len = self._bytes.?.len;
                self._bytes = try self.allocator.realloc(self._bytes.?, old_bytes_len + data_result.len);
            }

            @memcpy(self._bytes.?[old_bytes_len..], data_result);
        }
    }

    pub fn write(self: *Self, data: []const u8, compression: bool) anyerror!void {
        if (self._type == null) {
            return error.MissingMessageType;
        }

        var frame: Frame = .{ .allocator = self.allocator, .bytes = data };
        defer frame.deinit();
        frame.setLastFrame(self._lastMessage);
        frame.setCompression(compression);
        const frame_bytes: []u8 = try frame.write(self._type.?.into());
        self._bytes = try self.allocator.alloc(u8, frame_bytes.len);
        @memcpy(self._bytes.?, frame_bytes);
    }

    pub fn deinit(self: *Self) void {
        if (self._bytes != null) {
            self.allocator.free(self._bytes.?);
        }
        self.* = undefined;
    }
};
