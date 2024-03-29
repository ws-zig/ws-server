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

const ClientFile = @import("./client.zig");
const Client = ClientFile.Client;
const ErrorFile = @import("./error.zig");
const Error = ErrorFile.Error;

pub const HandshakeFn = ?*const fn (client: *Client, headers: *const std.StringHashMap([]const u8)) anyerror!bool;
pub const ErrorFn = ?*const fn (client: ?*Client, info: *const Error) anyerror!void;

pub const OStrFn = ?*const fn (client: *Client, data: ?[]const u8) anyerror!void;
pub const Fn = ?*const fn (client: *Client) anyerror!void;

pub const Callbacks = struct {
    handshake: HandshakeCallback = .{ .handler = null },
    disconnect: FnCallback = .{ .name = "Disconnect", .handler = null },
    err: ErrorCallback = .{ .handler = null },

    text: OStrCallback = .{ .name = "Text", .handler = null },
    binary: OStrCallback = .{ .name = "Binary", .handler = null },
    close: FnCallback = .{ .name = "Close", .handler = null },
    ping: FnCallback = .{ .name = "Ping", .handler = null },
    pong: FnCallback = .{ .name = "Pong", .handler = null },
};

const HandshakeCallback = struct {
    handler: HandshakeFn,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client, headers: *const std.StringHashMap([]const u8)) bool {
        if (self.handler != null) {
            const cb_result = self.handler.?(client, headers) catch |e| {
                std.debug.print("Handshake callback failed: {any}\n", .{e});
                return false;
            };
            return cb_result;
        }
        return true;
    }
};

const ErrorCallback = struct {
    handler: ErrorFn,

    const Self = @This();

    pub fn handle(self: *const Self, client: ?*Client, info: *const Error) void {
        if (self.handler != null) {
            self.handler.?(client, info) catch |e| {
                std.debug.print("Error callback failed: {any}\n", .{e});
            };
        }
    }
};

const OStrCallback = struct {
    name: []const u8,
    handler: OStrFn,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client, data: ?[]const u8) void {
        if (self.handler != null) {
            self.handler.?(client, data) catch |e| {
                std.debug.print("{s} callback failed: {any}\n", .{ self.name, e });
            };
        }
    }
};

const FnCallback = struct {
    name: []const u8,
    handler: Fn,

    const Self = @This();

    pub fn handle(self: *const Self, client: *Client) void {
        if (self.handler != null) {
            self.handler.?(client) catch |e| {
                std.debug.print("{s} callback failed: {any}\n", .{ self.name, e });
            };
        }
    }
};
