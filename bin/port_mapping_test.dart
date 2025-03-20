import 'dart:io';

enum ServerType { http, ws }

typedef ServerConfig = (ServerType, InternetAddress, int);

var port = 8000;
var servers = [
  (ServerType.http, InternetAddress.loopbackIPv4, port++),
  (ServerType.http, InternetAddress.anyIPv4, port++),
  (ServerType.http, InternetAddress.loopbackIPv6, port++),
  (ServerType.http, InternetAddress.anyIPv6, port++),
  (ServerType.ws, InternetAddress.loopbackIPv4, port++),
  (ServerType.ws, InternetAddress.anyIPv4, port++),
  (ServerType.ws, InternetAddress.loopbackIPv6, port++),
  (ServerType.ws, InternetAddress.anyIPv6, port++),
];

Future<void> main(List<String> arguments) async {
  await Future.wait([
    serveHelperPage(InternetAddress('0.0.0.0'), port++),
    ...servers.map(serve),
  ]);
}

Future<void> serveHelperPage(InternetAddress address, int port) async {
  try {
    var server = await HttpServer.bind(address, port);
    print('Helper server listening at http://127.0.0.1:$port/');
    await server.forEach((HttpRequest request) {
      request.response.headers.contentType = ContentType.html;
      request.response.write(r'''
      <html>
      <head>
        <style>
          .good { background-color: #ccffcc; }
          .bad { background-color: #ffcccc; }
        </style>
      </head>
      <body>
        <textarea id="servers" cols="80" rows="10"></textarea>
        <button onclick="startTest();">Test</button>
        <div id="log" style="width: 1000px; height: 600px"></div>
        <script>
        async function startTest() {
          console.log(document.getElementById('servers').value);
          const servers = document.getElementById('servers').value;
          const log = document.getElementById('log');

          log.innerHTML = '';
          for (const server of servers.split('\n').map((s) => s.trim())) {
            if (server.startsWith('http')) {
                try {
                  const response = await fetch(server);
                  if (!response.ok) {
                    throw new Error(`Response status: ${response.status}`);
                  }
                  log.innerHTML += `<p class="good"><code>${server}</code>: ${await response.text()}</p>`;
                } catch (error) {
                  log.innerHTML += `<p class="bad"><code>${server}</code>: ${error}</p>`;
                }
            } else if (server.startsWith('ws')) {
              await new Promise((resolve, reject) => {
                try {
                  const ws = new WebSocket(server);

                  ws.onopen = () => {
                    ws.onmessage = (event) => {
                      log.innerHTML += `<p class="good"><code>${server}</code>: ${event.data}</p>`;
                      ws.close();
                      resolve();
                    };

                    ws.onclose = () => {
                      resolve();
                    };
                  };

                  ws.onerror = (error) => {
                    log.innerHTML += `<p class="bad"><code>${server}</code>: ${error}</p>`;
                    resolve();
                  };
                } catch (e) {
                  log.innerHTML += `<p class="bad"><code>${server}</code>: ${e}</p>`;
                }
              });
            }
          }
        }
        </script>
      </body>
      </html>
''');
      request.response.close();
    });
  } catch (e) {
    print('Failed to bind HTTP $address:$port: $e');
  }
}

Future<void> serve(ServerConfig config) async {
  var (type, address, port) = config;
  return (type == ServerType.http ? serveHttp : serveWs)(address, port);
}

Future<void> serveHttp(InternetAddress address, int port) async {
  try {
    var server = await HttpServer.bind(address, port);
    printAddress('http', address, port);
    await server.forEach((HttpRequest request) {
      request.response.headers.add("Access-Control-Allow-Origin", "*");
      request.response.write(
        'A HTTP request on port $port of ${address.address}',
      );
      request.response.close();
    });
  } catch (e) {
    print('Failed to bind HTTP $address:$port: $e');
  }
}

Future<void> serveWs(InternetAddress address, int port) async {
  try {
    var server = await HttpServer.bind(address, port);
    printAddress('ws', address, port);
    await server
        .where(WebSocketTransformer.isUpgradeRequest)
        .map(WebSocketTransformer.upgrade)
        .forEach((Future<WebSocket> futureSocket) async {
          var socket = await futureSocket;
          socket.add(
            'A WebSocket connection on port $port of ${address.address}',
          );
        });
  } catch (e) {
    print('Failed to bind WS $address:$port: $e');
  }
}

void printAddress(String protocol, InternetAddress address, int port) {
  var accessibleAddress =
      (address == InternetAddress.anyIPv4)
          ? InternetAddress.loopbackIPv4
          : address == InternetAddress.anyIPv6
          ? InternetAddress.loopbackIPv6
          : address;

  var addressPart = accessibleAddress.address;
  if (addressPart == "::1") addressPart = "[::1]";
  print('$protocol://$addressPart:$port/');
}
