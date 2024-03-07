const std = @import("std");

const ws = @import("ws-server");
const Server = ws.Server;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var server = Server.create(&allocator, "127.0.0.1", 8080);
    server.setConfig(.{
        // Specifies how large a single received message can be.
        .msg_buffer_size = 65535, // default: 65535
        // Specifies how large a complete message can be.
        .max_msg_size = 131070, // default: std.math.maxInt(u32)

        // Experimental configurations should only be used for testing purposes.
        .experimental = .{
            // Enables support for PerMessageDeflate.
            .compression = true, // default: false
        },
    });
    try server.listen();
}
