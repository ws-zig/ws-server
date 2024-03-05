const { WebSocket } = require('ws');
const client = new WebSocket("ws://127.0.0.1:8080", {
    perMessageDeflate: true,
});

client.on('open', () => {
    client.send("Hello server!");
});

client.on('message', (msg) => {
    console.log(msg.toString());
});