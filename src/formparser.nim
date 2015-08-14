import asyncdispatch, asynchttpserver, strtabs, json, strutils, oids

type
    FormFile = object
        size: int
        path: string
        name: string
        mime: string
        lastModifiedDate: string

# --AaB03x\r\n 
# Content-Disposition: form-data; name="name1"\r\n\r\n 
# aaa\r\n 
# --AaB03x\r\n 
# Content-Disposition: form-data; name="a"; filename="file1.txt"\r\n 
# Content-Type: text/plain\r\n\r\n 
# 01010101\r\n 
# --AaB03x--\r\n


proc parse(req: Request) =
    echo "--- body               : ", req.body
    echo "--- has content type   : ", req.headers.hasKey("Content-Type")
    echo "--- has content length : ", req.headers.hasKey("Content-Length")
    echo "--- content type       : ", req.headers["Content-Type"]
    echo "--- content length     : ", req.headers["Content-Length"]
    
    var 
        fields: JsonNode 

    if (req.headers["Content-Type"] == "application/json"):
        fields = parseJson(req.body)
        echo fields.kind
        echo fields.fields
        echo fields["b"][0]["a"]

    if (req.headers["Content-Type"] == "application/x-www-form-urlencoded"):
        fields = newJObject()
        var x: seq[string] 
        for it in req.body.split('&'):
            x = it.split('=')
            case x.len():
            of 0: discard
            of 1: fields[x[0]] = newJNull()
            else: fields[x[0]] = newJString(x[1])
        echo fields

    if (req.headers["Content-Type"] == "application/octet-stream"):
        var tmpPath = "/home/king/tmp/"
        var filename = tmpPath & $genOid()
        writeFile(filename, req.body)
        echo filename

        var obj = newJObject()
        obj["size"] = newJInt(req.body.len())
        obj["path"] = newJString(filename)
        obj["name"] = newJNull()
        obj["mime"] = newJString("application/octet-stream")

        var options = newJArray()
        options.add(obj)

        var files = newJObject()
        files["anonymous"] = options

        echo files
        echo files["anonymous"][0]["size"]

when not defined(testing) and isMainModule:
    import asyncdispatch, asynchttpserver, asyncnet, threadpool, net, os

    proc server() =
        var server = newAsyncHttpServer()
        proc cb(req: Request) {.async.} =
            parse(req)
        waitFor server.serve(Port(8000), cb)

    proc client() =
        var 
            socket = newSocket()
        socket.connect("127.0.0.1", Port(8000)) 
        socket.send("POST /path HTTP/1.1\r\L")
        socket.send("Content-Type: text/plain\r\L")
        socket.send("Content-Length: 12\r\L\r\L")
        socket.send("Hello world!")

    proc clientJson() =
        var 
            socket = newSocket()
            data = """{"a":1, "b":[{"a":2}, {"c":3}], "c":null}"""    
        socket.connect("127.0.0.1", Port(8000)) 
        socket.send("POST /path HTTP/1.1\r\L")
        socket.send("Content-Type: application/json\r\L")
        socket.send("Content-Length: " & $data.len() & "\r\L\r\L")
        socket.send(data)

    proc clientUrlencoded() =
        var 
            socket = newSocket()
            data = """a=100&b=200&&x&&m&&"""    
        socket.connect("127.0.0.1", Port(8000)) 
        socket.send("POST /path HTTP/1.1\r\L")
        socket.send("Content-Type: application/x-www-form-urlencoded\r\L")
        socket.send("Content-Length: " & $data.len() & "\r\L\r\L")
        socket.send(data)

    proc clientOctetStream() =
        var 
            socket = newSocket()
            data = """000000"""    
        socket.connect("127.0.0.1", Port(8000)) 
        socket.send("POST /path HTTP/1.1\r\L")
        socket.send("Content-Type: application/octet-stream\r\L")
        socket.send("Content-Length: " & $data.len() & "\r\L\r\L")
        socket.send(data)

    proc clientMultipart() =
        var 
            socket = newSocket()
            data = """--AaB03x
Content-Disposition: form-data; name="name1"

aaa
--AaB03x
Content-Disposition: form-data; name="a"; filename="file1.txt"
Content-Type: text/plain

01010101
--AaB03x--"""    
        socket.connect("127.0.0.1", Port(8000)) 
        socket.send("POST /path HTTP/1.1\r\L")
        socket.send("Content-Type: multipart/form-data; boundary=AaB03x\r\L")
        socket.send("Content-Length: " & $data.len() & "\r\L\r\L")
        socket.send(data)
   
    proc main() =
        parallel:
            spawn server()
            sleep(100)
            spawn clientMultipart()

    main()



    
