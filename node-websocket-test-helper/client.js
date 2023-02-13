var url = require('url');
var WebSocket = require('ws');
var HttpsProxyAgent = require('https-proxy-agent');
var HttpProxyAgent = require('http-proxy-agent');

// HTTP/HTTPS proxy to connect to
var proxy = process.env.http_proxy || 'http://127.0.0.1:8080';
console.log('using proxy server %j', proxy);

// WebSocket endpoint for the proxy to connect to
var endpoint = process.argv[2] || 'wss://127.0.0.1:9999';
var parsed = url.parse(endpoint);
console.log('attempting to connect to WebSocket %j', endpoint);

// create an instance of the `HttpsProxyAgent` class with the proxy server information
var options = url.parse(proxy);

var agent = new HttpProxyAgent({...options});

// finally, initiate the WebSocket connection
var socket = new WebSocket(endpoint, { agent: agent });

socket.on('open', function () {
  console.log('"open" event!');
  socket.send('hello world11111');

  setTimeout(() => {
    socket.send('content from the node ws client')
  }, 5);
});

socket.on('message', function (data, flags) {
  console.log('"message" event! %s %j', data, flags);
  // socket.close();
});

socket.on('error', (code, error) => {
  console.log('error', code, error)
})

socket.on('close', (code , error) => {
  console.log('close', code, error)
})

// setInterval(function() {
//   console.log("timer that keeps nodejs processing running");
// }, 1000 * 60 * 60);
