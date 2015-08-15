import ../httpform, asyncdispatch, asynchttpserver,
       threadpool, net, os, strtabs, json

proc server() =
    var 
        server = newAsyncHttpServer()
        form = newAsyncHttpForm("/home/king/tmp", true)
    proc cb(req: Request) {.async.} =
        var (fields, files) = await form.parseAsync(req.headers["Content-Type"], req.body)
        assert fields["b"][0]["a"] == newJInt(2)
        assert files               == nil
        quit(0)
    waitFor server.serve(Port(8000), cb)

proc client() =
    var 
        socket = newSocket()
        data = """{"a":1, "b":[{"a":2}, {"c":3}], "c":null}"""    
    socket.connect("127.0.0.1", Port(8000)) 
    socket.send("POST /path HTTP/1.1\r\L")
    socket.send("Content-Type: application/json\r\L")
    socket.send("Content-Length: " & $data.len() & "\r\L\r\L")
    socket.send(data)
    
proc main() =
    parallel:
        spawn server()
        sleep(100)
        spawn client()

main()
