import ../httpform, asyncdispatch, asynchttpserver,
       threadpool, net, os, strtabs, json

proc server() =
    var 
        server = newAsyncHttpServer()
        form = newAsyncHttpForm(getTempDir(), true)
    proc cb(req: Request) {.async.} =
        var (fields, files) = await form.parseAsync(req.headers["Content-Type"], req.body)
        assert fields["username"]         == newJString("Tom")
        echo   files["upload"][0]["path"] #  "/home/king/tmp/55cdf98a0fbeb30400000000.txt"
        assert files["upload"][0]["size"] == newJInt(6)
        assert files["upload"][0]["type"] == newJString("text/plain")
        assert files["upload"][0]["name"] == newJString("file1.txt")
        echo   files["upload"][1]["path"] #  "/home/king/tmp/55cdf98a0fbeb30400000001.gif"
        assert files["upload"][1]["size"] == newJInt(12)
        assert files["upload"][1]["type"] == newJString("image/gif")
        assert files["upload"][1]["name"] == newJString("file2.gif")
        quit(0)
    waitFor server.serve(Port(8000), cb)

proc client() =
    var 
        socket = newSocket()
        data = "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"username\"\r\n\r\n" &
                "Tom\r\n" &

                "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"upload\"; filename=\"file1.txt\"\r\n" &
                "Content-Type: text/plain\r\n\r\n" & 
                "000000\r\n" &

                "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"upload\"; filename=\"file2.gif\"\r\n" &
                "Content-Type: image/gif\r\n" &
                "Content-Transfer-Encoding: base64\r\n\r\n" &
                "010101010101\r\n" &

                "--AaB03x--\r\n"
            
    socket.connect("127.0.0.1", Port(8000)) 
    socket.send("POST /path HTTP/1.1\r\L")
    socket.send("Content-Type: multipart/form-data; boundary=AaB03x\r\L")
    socket.send("Content-Length: " & $data.len() & "\r\L\r\L")
    socket.send(data)
    
proc main() =
    parallel:
        spawn server()
        sleep(100)
        spawn client()

main()
