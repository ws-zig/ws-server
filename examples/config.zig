const std = @import("std");

const ws = @import("ws-server");
const Server = ws.Server;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var server = Server.create(&allocator, "127.0.0.1", 8080);
    server.setConfig(.{
        // A larger buffer allows a larger message to be received.
        .buffer_size = 65535, // default: 65535
    });
    try server.listen();
}
