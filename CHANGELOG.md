# Changelog
## [v0.3.0](https://github.com/ws-zig/ws-server/tree/v0.3.0) (2024-03-05 UTC+1)
> [!NOTE]
> The upcoming Zig(-lang) version [**0.12.0**](https://github.com/ziglang/zig/tree/0b744da844e4172ec0c695098e67ab2a7184c5f0) is supported.

**Changed**
- The required Zig(-lang) version has been increased to **0.12.0**.
- The callback argument `data: []const u8` has been changed to `data: ?[]const u8`.

**Added**
- `experimental` server configuration.
- - All experimental configurations should only be used for testing purposes!
- [Experimental] Support for compression (perMessageDeflate).
- - Use `server.setConfig(.{ .experimental = .{ .compression = true } })` to enable compression.
  - The header `Sec-WebSocket-Extensions: permessage-deflate` is required during the handshake, otherwise the client will be disconnected!

**Other**
- Many improvements, bug fixes and more.
- - [Click here to compare all changes.](https://github.com/ws-zig/ws-server/compare/v0.2.1...v0.3.0)

## [v0.2.1](https://github.com/ws-zig/ws-server/tree/v0.2.1) (2024-03-04 UTC+1)
> [!NOTE]
> The current Zig(-lang) version [**0.11.0**](https://github.com/ziglang/zig/releases/tag/0.11.0) is supported.

**Fixed**
- Send and receive large data on `AArch64`.
- - With v0.2.0 we only checked `x86_64` for data type `u64`.
- `text()` and `binary()` with exactly 65531 bytes.
- - Data with exactly 65531 bytes never arrived at the client marked as complete.
- `textAll()` and `binaryAll()` with to large data and unsupported data type `u64`.
- - The data is now automatically sent to the client as "chunks" if the size is over 65531 bytes and the data type `u64` is not supported.

**Known issues**
- Console error on Windows when client disconnects.
- - An error message is displayed in the console which can be ignored. The error is only displayed if the client disconnects during a callback. The problem was fixed with Zig(-lang) in version 0.12.0.

## [v0.2.0](https://github.com/ws-zig/ws-server/tree/v0.2.0) (2024-02-29 UTC+1)
> [!NOTE]
> The current Zig(-lang) version [**0.11.0**](https://github.com/ziglang/zig/releases/tag/0.11.0) is supported.

**Changed**
- `sendText()`
- - This function is now called `text()`. The data is now sent in chunks (65535 bytes each).
- `sendBinary()`
- - This function is now called `binary()`. The data is now sent in chunks (65535 bytes each).
- `sendClose()`
- - This function is now called `close()`.
- `sendPing()`
- - This function is now called `ping()`.
- `sendPong()`
- - This function is now called `pong()`.

**Added**
- Support for sending large messages as multiple small ones.
- - Data longer than 65531 bytes is sent as "chunks", meaning the server sends multiple messages containing parts of the large message with a maximum of 65535 bytes (the client processes the messages as one complete once the last one is received).
- `textAll()`
- - This function replaces the previous `sendText()`.
- `binaryAll()`
- - This function replaces the previous `sendBinary()`.

**Fixed**
- Compiling for 32-bit architectures was not possible and resulted in an error.
- - The `text()` or `binary()` function should be used for 32-bit architectures with more than 65531 bytes of data. Also make sure that no more than 65535 bytes (65531 bytes + frame) are sent from the client at once. Anything over 65535 bytes (65531 bytes + frame) of data requires 64-bit architecture (u64 data type).

**Other**
- General improvements.

## [v0.1.0](https://github.com/ws-zig/ws-server/tree/v0.1.0) (2024-02-27 UTC+1)
> [!NOTE]
> The current Zig(-lang) version [**0.11.0**](https://github.com/ziglang/zig/releases/tag/0.11.0) is supported.
