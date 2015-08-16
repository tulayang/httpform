import strutils, os, oids, base64, asyncfile, asyncdispatch, json

include "./multipart"

type
    HttpForm = ref object
        tmp: string
        keepExtname: bool
    AsyncHttpForm = HttpForm

template newHttpFormImpl(result: expr) =
    new(result)
    result.tmp = tmp
    result.keepExtname = keepExtname

proc newHttpForm*(tmp: string, keepExtname = true): HttpForm =
    newHttpFormImpl(result)

proc newAsyncHttpForm*(tmp: string, keepExtname = true): AsyncHttpForm =
    newHttpFormImpl(result)

proc parseUrlencoded(body: string): JsonNode {.inline.} =
    var 
        a: seq[string] 
        i, h: int
    result = newJObject()
    for s in body.split('&'):
        if s.len() == 0 or s == "=":
            result[""] = newJString("")
        else:
            i = s.find('=')
            h = s.high()
            if i == -1:
                result[s] = newJString("")
            elif i == 0:
                result[""] = newJString(s[i+1..h])
            elif i == h:
                result[s[0..h-1]] = newJString("")
            else:
                result[s[0..i-1]] = newJString(s[i+1..h])

template parseOctetStreamImpl(write: stmt) {.immediate.} =
    var options = newJArray()
    options.add(newFile(path, body.len(), "application/octet-stream", nil))
    result = newJObject()
    result[nil] = options
    write

proc parseOctetStream(body: string, tmp: string): JsonNode {.tags: [WriteIOEffect].} =
    var path = joinPath(tmp, $genOid())
    parseOctetStreamImpl: 
        writeFile(path, body)

proc parseOctetStreamAsync(body: string, tmp: string): Future[JsonNode] 
                          {.async, tags: [WriteIOEffect, RootEffect].} =
    var path = joinPath(tmp, $genOid())
    parseOctetStreamImpl: 
        await writeFileAsync(path, body)

proc parseUnknown(body: string): JsonNode =
    result = newJObject()
    result[nil] = newJString(body)

proc parse*(x: HttpForm, contentType: string, body: string):
           tuple[fields: JsonNode, files: JsonNode]
           {.tags: [WriteIOEffect, ReadIOEffect].} =  
    var 
        i: int  
        s: string
    if not body.isNil() and body.len() > 0:
        if contentType.isNil():
            raise newException(FormError, "bad content-type header, no content-type")
        case contentType.toLower()
        of "application/json": 
            result.fields = body.parseJson()
        of "application/x-www-form-urlencoded": 
            result.fields = body.parseUrlencoded()
        of "application/octet-stream": 
            result.files = body.parseOctetStream(x.tmp)
        else:
            s = contentType.toLower()
            i = s.find("multipart/form-data; ")
            if i == 0:
                i = s.find("boundary=")
                if i > -1 and i + "boundary=".len() < s.len():
                    result = body.parseMultipart(contentType[i + "boundary=".len()..s.len()-1], 
                                                 x.tmp, x.keepExtname)
                else:
                    raise newException(FormError, "bad content-type header, no multipart boundary")
            else:
                result.fields = body.parseUnknown()

proc parseAsync*(x: AsyncHttpForm, contentType: string, body: string):
                Future[tuple[fields: JsonNode, files: JsonNode]]
                {.async, tags: [RootEffect, WriteIOEffect, ReadIOEffect].} =  
    var 
        i: int  
        s: string  
    if not body.isNil() and body.len() > 0:
        if contentType.isNil():
            raise newException(FormError, "bad content-type header, no content-type")
        case contentType.toLower()
        of "application/json": 
            result.fields = body.parseJson()
        of "application/x-www-form-urlencoded": 
            result.fields = body.parseUrlencoded()
        of "application/octet-stream": 
            result.files = await body.parseOctetStreamAsync(x.tmp)
        else:
            s = contentType.toLower()
            i = s.find("multipart/form-data; ")
            if i == 0:
                i = s.find("boundary=")
                if i > -1 and i + "boundary=".len() < s.len():
                    result = await body.parseMultipartAsync(contentType[i + "boundary=".len()..s.len()-1], 
                                                            x.tmp, x.keepExtname)
                else:
                    raise newException(FormError, "bad content-type header, no multipart boundary")
            else:
                result.fields = body.parseUnknown()

when isMainModule:
    proc main() =
        var 
            data = 
                "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"username\"\r\n\r\n" &
                "Tom\r\n" &

                "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"upload\"; filename=\"file1.txt\"\r\n" &
                "Content-Type: text/plain\r\n\r\n" & 
                "000000\r\n" &
                "111111\r\n" &
                "010101\r\n\r\n" &

                "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"upload\"; filename=\"file2.gif\"\r\n" &
                "Content-Type: image/gif\r\n" &
                "Content-Transfer-Encoding: base64\r\n\r\n" &
                "010101010101\r\n" &

                "--AaB03x--\r\n"
            
            form = newHttpForm(getTempDir())

            (fields, files) = form.parse("multipart/form-data; boundary=AaB03x", data)

        assert fields["username"]         == newJString("Tom")
        echo   files["upload"][0]["path"] #  "/home/king/tmp/55cdf98a0fbeb30400000000.txt"
        assert files["upload"][0]["size"] == newJInt(24)
        assert files["upload"][0]["type"] == newJString("text/plain")
        assert files["upload"][0]["name"] == newJString("file1.txt")
        echo   files["upload"][1]["path"] #  "/home/king/tmp/55cdf98a0fbeb30400000001.gif"
        assert files["upload"][1]["size"] == newJInt(12)
        assert files["upload"][1]["type"] == newJString("image/gif")
        assert files["upload"][1]["name"] == newJString("file2.gif")

    proc mainAsync() {.async.} =
        var 
            data = 
                "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"username\"\r\n\r\n" &
                "Tom\r\n" &

                "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"upload\"; filename=\"file1.txt\"\r\n" &
                "Content-Type: text/plain\r\n\r\n" & 
                "000000\r\n" &
                "111111\r\n" &
                "010101\r\n\r\n" &

                "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"upload\"; filename=\"file2.gif\"\r\n" &
                "Content-Type: image/gif\r\n" &
                "Content-Transfer-Encoding: base64\r\n\r\n" &
                "010101010101\r\n" &

                "--AaB03x--\r\n"
            
            form = newAsyncHttpForm(getTempDir())

            (fields, files) = await form.parseAsync("multipart/form-data; boundary=AaB03x", data)

        assert fields["username"]         == newJString("Tom")
        echo   files["upload"][0]["path"] #  "/home/king/tmp/55cdf98a0fbeb30400000000.txt"
        assert files["upload"][0]["size"] == newJInt(24)
        assert files["upload"][0]["type"] == newJString("text/plain")
        assert files["upload"][0]["name"] == newJString("file1.txt")
        echo   files["upload"][1]["path"] #  "/home/king/tmp/55cdf98a0fbeb30400000001.gif"
        assert files["upload"][1]["size"] == newJInt(12)
        assert files["upload"][1]["type"] == newJString("image/gif")
        assert files["upload"][1]["name"] == newJString("file2.gif")
        # poll()
        # poll()

    asyncCheck mainAsync()
    #main()