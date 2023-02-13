// import { WebSocketServer } from 'ws';
const ws = require('ws')
const WebSocketServer = ws.WebSocketServer

const wss = new WebSocketServer({ port: 9999 });

wss.on('connection', function connection(ws) {
  console.log('has a connection')
  ws.on('error', console.error);

  ws.on('message', function message(data) {
    console.log('received: %s', data);
    ws.send('server---:' + data);

    console.log(data === 'close')
    if (data == 'close') {
      console.log('--------------------close')
      ws.close()
    }
  });

  ws.send('from server something');
});
console.log('server start')