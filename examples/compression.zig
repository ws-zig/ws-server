const std = @import("std");

const ws = @import("ws-server");
const Server = ws.Server;
const Client = ws.Client;

fn _onText(client: *Client, data: ?[]const u8) anyerror!void {
    if (data) |data_result| {
        std.debug.print("{s}\n", .{data_result});
    }
    _ = try client.textAll("Hello client!");
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = Server.create(&allocator, "127.0.0.1", 8080);
    server.setConfig(.{
        .experimental = .{
            // Allow compression (perMessageDeflate).
            .compression = true,
        },
    });
    server.onText(&_onText);
    try server.listen();
}
