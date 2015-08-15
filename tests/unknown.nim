import ../httpform, asyncdispatch, asynchttpserver,
       threadpool, net, os, strtabs, json

proc server() =
    var 
        server = newAsyncHttpServer()
        form = newAsyncHttpForm(getTempDir(), true)
    proc cb(req: Request) {.async.} =
        var (fields, files) = await form.parseAsync(req.headers["Content-Type"], req.body)
        assert fields[nil] == newJString("Hello world!")
        assert files       == nil
        quit(0)
    waitFor server.serve(Port(8000), cb)

proc client() =
    var 
        socket = newSocket()
    socket.connect("127.0.0.1", Port(8000)) 
    socket.send("POST /path HTTP/1.1\r\L")
    socket.send("Content-Type: text/plain\r\L")
    socket.send("Content-Length: 12\r\L\r\L")
    socket.send("Hello world!")

proc main() =
    parallel:
        spawn server()
        sleep(100)
        spawn client()

main()
