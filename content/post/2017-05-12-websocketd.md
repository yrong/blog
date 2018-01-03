---
author: Ron
catalog: true
date: 2017-05-12T00:00:00Z
header-img: img/post-bg-2015.jpg
tags:
- golang
title: websocketd code analysis
url: /2017/05/12/websocketd/
---

websocketd is a small command-line tool that will wrap an existing command-line interface program, and allow it to be accessed via a WebSocket.

<!--more-->

WebSocket-capable applications can now be built very easily. As long as you can write an executable program that reads STDIN and writes to STDOUT, you can build a WebSocket server. Do it in Python, Ruby, Perl, Bash, .NET, C, Go, PHP, Java, Clojure, Scala, Groovy, Expect, Awk, VBScript, Haskell, Lua, R, whatever! No networking libraries necessary.

## Understanding the basics

A WebSocket endpoint is a program that you expose over a WebSocket URL (e.g. ws://someserver/my-program). Everytime a browser connects to that URL, the websocketd server will start a new instance of your process. When the browser disconnects, the process will be stopped.

If there are 10 browser connected to your server, there will be 10 independent instances of your program running. websocketd takes care of listening for WebSocket connections and starting/stopping your program processes.

If your process needs to send a WebSocket message it should print the message contents to STDOUT, followed by a new line. websocketd will then send the message to the browser.

As you'd expect, if the browser sends a WebSocket message, websocketd will send it to STDIN of your process, followed by a new line.

## Building a web-page that connects to the WebSocket

```
var ws = new WebSocket('ws://localhost:8080/');
ws.onopen    = function() { ... do something on connect ... };
ws.onclose   = function() { ... do something on disconnect ... };
ws.onmessage = function(event) { ... do something with event.data ... };
```

## CoreLogic

```
//main.go
//add http handler
handler := libwebsocketd.NewWebsocketdServer(config.Config, log, config.MaxForks)
http.Handle("/", handler)
```

```
//http.go
//implement ServerHTTP method and server websocket upgrade
func (h *WebsocketdServer) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	if strings.ToLower(hdrs.Get("Upgrade")) == "websocket" && upgradeRe.MatchString(hdrs.Get("Connection")) {
    			if h.noteForkCreated() == nil {
    				defer h.noteForkCompled()

    				handler, err := NewWebsocketdHandler(h, req, log)
    				if err != nil {
    					if err == ScriptNotFoundError {
    						log.Access("session", "NOT FOUND: %s", err)
    						http.Error(w, "404 Not Found", 404)
    					} else {
    						log.Access("session", "INTERNAL ERROR: %s", err)
    						http.Error(w, "500 Internal Server Error", 500)
    					}
    					return
    				}

    				// Now we are ready for connection upgrade dance...
    				wsServer := &websocket.Server{
    					Handshake: h.wshandshake(log),
    					Handler:   handler.wshandler(log),
    				}
    				wsServer.ServeHTTP(w, req)//server websocket
    			} else {
    				log.Error("http", "Max of possible forks already active, upgrade rejected")
    				http.Error(w, "429 Too Many Requests", 429)
    			}
    			return
    		}
}
```

```
//handler.go
//pipeline stream between processEndpoint and wsEndpoint
func (wsh *WebsocketdHandler) accept(ws *websocket.Conn, log *LogScope) {
defer ws.Close()

	log.Access("session", "CONNECT")
	defer log.Access("session", "DISCONNECT")

	launched, err := launchCmd(wsh.command, wsh.server.Config.CommandArgs, wsh.Env)
	if err != nil {
		log.Error("process", "Could not launch process %s %s (%s)", wsh.command, strings.Join(wsh.server.Config.CommandArgs, " "), err)
		return
	}

	log.Associate("pid", strconv.Itoa(launched.cmd.Process.Pid))
	log.Info("session",strconv.Itoa(launched.cmd.Process.Pid))

	binary := wsh.server.Config.Binary
	process := NewProcessEndpoint(launched, binary, log)
	if cms := wsh.server.Config.CloseMs; cms != 0 {
		process.closetime += time.Duration(cms) * time.Millisecond
	}
	wsEndpoint := NewWebSocketEndpoint(ws, binary, log)

	PipeEndpoints(process, wsEndpoint)
}
```

```
//endpoint.go
//read message from channel of one endpoint and pipe to the other endpoint stream
func PipeEndpoints(e1, e2 Endpoint) {
	e1.StartReading()
	e2.StartReading()

	defer e1.Terminate()
	defer e2.Terminate()
	for {
		select {
		case msgOne, ok := <-e1.Output():
			log.Println(string(msgOne))
			if !ok || !e2.Send(msgOne) {
				return
			}
		case msgTwo, ok := <-e2.Output():
			log.Println(string(msgTwo))
			if !ok || !e1.Send(msgTwo) {
				return
			}
		}
	}
}
```

```
//process_endpoint.go
//read output from process and add to channel in goroutine
func (pe *ProcessEndpoint) StartReading() {
	go pe.log_stderr()
	if pe.bin {
		go pe.process_binout()
	} else {
		go pe.process_txtout()
	}
}

func (pe *ProcessEndpoint) process_txtout() {
	bufin := bufio.NewReader(pe.process.stdout)
	for {
	    //ReadBytes reads until the first occurrence of delim in the input,so process should use '\n' as splitter
		buf, err := bufin.ReadBytes('\n')
		if err != nil {
			if err != io.EOF {
				pe.log.Error("process", "Unexpected error while reading STDOUT from process: %s", err)
			} else {
				pe.log.Debug("process", "Process STDOUT closed")
			}
			break
		}
		pe.output <- trimEOL(buf)
	}
	close(pe.output)
}
```

```
//websocket_endpoint.go
//read output from websocket and add to channel in goroutine
func (we *WebSocketEndpoint) StartReading() {
	if we.bin {
		go we.read_binary_frames()
	} else {
		go we.read_text_frames()
	}
}

func (we *WebSocketEndpoint) read_text_frames() {
	for {
		var msg string
		err := websocket.Message.Receive(we.ws, &msg)
		if err != nil {
			if err != io.EOF {
				we.log.Debug("websocket", "Cannot receive: %s", err)
			}
			break
		}
		we.output <- append([]byte(msg), '\n')
	}
	close(we.output)
}
```