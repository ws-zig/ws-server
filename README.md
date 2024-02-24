A simple WebSocket server for the Zig(-lang) programming language. Feel free to contribute and improve this implementation.

## Installation
- [Download the source code](https://github.com/ws-zig/ws-server/archive/refs/heads/main.zip).
- Unzip the folder somewhere.
- Open your `build.zig`.
- Look for the following code:
```zig
    const exe = b.addExecutable(.{
        .name = "...",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
```
- Paste the following source code below:
```zig
    const wsServerModule = b.addModule("ws-server", .{ .source_file = .{ .path = "PATH_TO_DIRECTORY/ws-server-main/src/main.zig" } });
    exe.addModule("ws-server", wsServerModule);
```
- Save the file and you're done!

#### To build or run your project, you can use the following commands:
- build: `zig build`
- run: `zig run .\src\main.zig --deps ws-server --mod ws-server::PATH_TO_DIRECTORY\ws-server-main\src\main.zig`

## Example
### Server:
This little example starts a server on port `8080` and sends `Hello!` to the client, whenever a text message arrives.
```zig
const std = @import("std");

const ws = @import("ws-server");
const Server = ws.Server;
const Client = ws.Client;

fn _onText(client: *Client, data: []const u8) anyerror!void {
    std.debug.print("MESSAGE RECEIVED: {s}\n", .{data});
    try client.sendText("Hello!");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var server = Server.create(&allocator, "127.0.0.1", 8080);
    server.onText(&_onText);
    try server.listen();
}
```

### Client:
For testing we use [NodeJS](https://nodejs.org/) with the [`ws`](https://www.npmjs.com/package/ws) package.
```js
const { WebSocket } = require('ws');
const client = new WebSocket("ws://127.0.0.1:8080");

client.on('open', () => {
  console.log("CONNECTED!");
  client.send("Hello server!");
});

client.on('message', (msg) => {
  console.log(msg.toString());
});

client.on('error', (err) => {
  console.error("ERROR: ", err);
  console.error("rawPacket: ", err.rawPacket?.toString());
});

client.on('close', () => {
  console.log("DISCONNECTED!");
});
```

### Result:

![Screenshot 2024-02-22 102939](https://github.com/ws-zig/ws-server/assets/154023155/55639635-574b-4a82-a020-7809f2eae31f)
