import ../httpform, asyncdispatch, asynchttpserver,
       threadpool, net, os, strtabs, json

proc server() =
    var 
        server = newAsyncHttpServer()
        form = newAsyncHttpForm(getTempDir(), true)
    proc cb(req: Request) {.async.} =
        var (fields, files) = await form.parseAsync(req.headers["Content-Type"], req.body)
        assert fields == nil
        echo   files[nil][0]["path"] 
        assert files[nil][0]["size"] == newJInt(6)
        assert files[nil][0]["name"] == newJString(nil)
        assert files[nil][0]["type"] == newJString("application/octet-stream")
        quit(0)
    waitFor server.serve(Port(8000), cb)

proc client() =
    var 
        socket = newSocket()
        data = "000000"   
    socket.connect("127.0.0.1", Port(8000)) 
    socket.send("POST /path HTTP/1.1\r\n")
    socket.send("Content-Type: application/octet-stream\r\n")
    socket.send("Content-Length: " & $data.len() & "\r\n\r\n")
    socket.send(data)
    
proc main() =
    parallel:
        spawn server()
        sleep(100)
        spawn client()

main()
