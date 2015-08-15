import strutils, os, oids, base64, asyncfile, asyncdispatch, json

type
    FormError = object of Exception
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

proc writeFileAsync(path: string, content: string) {.async.} =
    var file = openAsync(path, fmWrite)
    await file.write(content)
    file.close()

proc parseUrlencoded(body: string): JsonNode {.inline.} =
    var a: seq[string] 
    result = newJObject()
    for pair in body.split('&'):
        a = pair.split('=')
        case a.len():
        of 0: discard
        of 1: result[a[0]] = newJNull()
        else: result[a[0]] = newJString(a[1])

proc newFile(path: string, size: int, ctype: string, filename: string): JsonNode = 
    result = newJObject()
    result["path"] = newJString(path)
    result["size"] = newJInt(size)
    result["type"] = newJString(ctype)
    result["name"] = newJString(filename)

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

template parseMultipartImpl(walk: stmt) {.immediate.} =
    proc delQuote(body: string): string =
    # "a" => a
        var length = body.len()
        if body == "\"\"": 
            return ""
        if length < 3: 
            return body
        if body[0] == '\"' and body[length-1] == '\"': 
            return body[1..length-2]
        return body

    proc reset() {.inline.} =
        disposition = nil
        name = nil
        filename = nil
        encoding = nil
        ctype = nil

    proc moveLine() {.inline.} = 
        if head == length:
            text = ""
            return
        while true:
            if tail == length:
                text = body[head..tail-1]
                head = tail
                return
            if body[tail] == '\13':              # \r
                if tail + 1 < length: 
                    if body[tail + 1] == '\10':  # \n
                        text = body[head..tail-1]
                        tail = tail + 2
                        head = tail
                        return
                else:
                    text = body[head..tail]
                    tail = tail + 1
                    head = tail
                    return
            inc(tail)
  
    proc moveParagraph() {.inline.} =
        if head == length:
            text = ""
            return
        while true:
            if tail == length:
                text = body[head..tail-1]
                head = tail
                return
            if body[tail] == '\13': 
                if tail + 3 < length:
                    if body[tail] == '\13'     and body[tail + 1] == '\10' and 
                       body[tail + 2] == '\13' and body[tail + 3] == '\10':  # \r\n\r\n
                        text = body[head..tail-1]
                        tail = tail + 4
                        head = tail
                        return
                else:
                    text = body[head..tail+2]
                    tail = tail + 3
                    head = tail
                    return
            inc(tail)

    proc pickParagraph() {.inline.} =
        var lineItems, dispItems, dispOptItems: seq[string]
        for line in text.split("\r\n"):
            lineItems = line.split(": ")
            if lineItems.len() == 2:
                case lineItems[0].toLower()
                of "content-disposition":
                    dispItems = lineItems[1].split("; ")
                    if dispItems[0] == "form-data":
                        disposition = dispItems[0]
                        for disp in dispItems:
                            dispOptItems = disp.split("=")
                            if dispOptItems.len() == 2:
                                case dispOptItems[0].toLower()
                                of "name":
                                    name = dispOptItems[1].delQuote()
                                of "filename":
                                    filename = dispOptItems[1].delQuote()
                                else:
                                    discard
                of "content-type":
                    ctype = lineItems[1]
                of "content-transfer-Encoding":
                    encoding = lineItems[1]
                else:
                    discard

    walk

proc parseMultipart(body: string, boundry: string, tmp: string, keepExtname: bool):
                   tuple[fields: JsonNode, files: JsonNode]
                   {.tags: [WriteIOEffect].} =
    var
        beginTk = "--" & boundry
        endTk = "--" & boundry & "--"
        length = body.len()
        text = ""
        head = 0
        tail = 0
        disposition, name, filename, encoding, ctype: string
        path: string
    parseMultipartImpl:
        result.fields = newJObject()
        result.files = newJObject()
        while true:
            if tail == length: break
            moveLine()
            if text == endTk: break
            if text != beginTk: continue
            moveParagraph()
            if text == "": break
            pickParagraph()
            if (disposition == "form-data"):
                moveLine()
                if filename.isNil():  
                # fields # and not name.isNil()
                    result.fields[name] = newJString(text)
                else: 
                # files # if not name.isNil():
                    path = joinPath(tmp, if keepExtname: $genOid() & splitFile(filename).ext
                                         else: $genOid())
                    case encoding
                    of nil, "binary", "7bit", "8bit": writeFile(path, text)  
                    of "base64": writeFile(path, decode(text))
                    else: raise newException(FormError, "unknow transfer encoding")  
                    if not result.files.hasKey(name): result.files[name] = newJArray()
                    result.files[name].add(newFile(path, text.len(), ctype, filename)) 
            reset()  

proc parseMultipartAsync(body: string, boundry: string, tmp: string, keepExtname: bool): 
                        Future[tuple[fields: JsonNode, files: JsonNode]]
                        {.async, tags: [RootEffect, WriteIOEffect].} =
    var
        beginTk = "--" & boundry
        endTk = "--" & boundry & "--"
        length = body.len()
        text = ""
        head = 0
        tail = 0
        disposition, name, filename, encoding, ctype: string
        path: string
    parseMultipartImpl:
        result.fields = newJObject()
        result.files = newJObject()
        while true:
            if tail == length: break
            moveLine()
            if text == endTk: break
            if text != beginTk: continue
            moveParagraph()
            if text == "": break
            pickParagraph()
            if (disposition == "form-data"):
                moveLine()
                if filename.isNil():  
                # fields # and not name.isNil()
                    result.fields[name] = newJString(text)
                else: 
                # files # if not name.isNil():
                    path = joinPath(tmp, if keepExtname: $genOid() & splitFile(filename).ext
                                         else: $genOid())
                    case encoding
                    of nil, "binary", "7bit", "8bit": await writeFileAsync(path, text) 
                    of "base64": await writeFileAsync(path, decode(text))
                    else: raise newException(FormError, "unknow transfer encoding")  
                    if not result.files.hasKey(name): result.files[name] = newJArray()
                    result.files[name].add(newFile(path, text.len(), ctype, filename)) 
            reset() 

proc parse*(x: HttpForm, contentType: string, body: string):
           tuple[fields: JsonNode, files: JsonNode]
           {.tags: [WriteIOEffect, ReadIOEffect].} =    
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
            if contentType.toLower().contains("multipart/form-data"):
                var cs = contentType.split("; ")
                if cs.len() < 2:
                    raise newException(FormError, "bad content-type header, no multipart boundary")
                var bs = cs[1].split("=")
                if bs.len() < 2 or bs[0] != "boundary" or bs[1].len() == 0:
                    raise newException(FormError, "bad content-type header, no multipart boundary")
                result = body.parseMultipart(bs[1], x.tmp, x.keepExtname)
            else:
                result.fields = body.parseUnknown()

proc parseAsync*(x: AsyncHttpForm, contentType: string, body: string):
                Future[tuple[fields: JsonNode, files: JsonNode]]
                {.async, tags: [RootEffect, WriteIOEffect, ReadIOEffect].} =    
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
            if contentType.toLower().contains("multipart/form-data"):
                var cs = contentType.split("; ")
                if cs.len() < 2:
                    raise newException(FormError, "bad content-type header, no multipart boundary")
                var bs = cs[1].split("=")
                if bs.len() < 2 or bs[0] != "boundary" or bs[1].len() == 0:
                    raise newException(FormError, "bad content-type header, no multipart boundary")
                result = await body.parseMultipartAsync(bs[1], x.tmp, x.keepExtname)
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

                "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"upload\"; filename=\"file2.gif\"\r\n" &
                "Content-Type: image/gif\r\n" &
                "Content-Transfer-Encoding: base64\r\n\r\n" &
                "010101010101\r\n" &

                "--AaB03x--\r\n"
            
            form = newHttpForm("/home/king/tmp")

            (fields, files) = form.parse("multipart/form-data; boundary=AaB03x", data)

        assert fields["username"]         == newJString("Tom")
        echo   files["upload"][0]["path"] #  "/home/king/tmp/55cdf98a0fbeb30400000000.txt"
        assert files["upload"][0]["size"] == newJInt(6)
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

                "--AaB03x\r\n" &
                "Content-Disposition: form-data; name=\"upload\"; filename=\"file2.gif\"\r\n" &
                "Content-Type: image/gif\r\n" &
                "Content-Transfer-Encoding: base64\r\n\r\n" &
                "010101010101\r\n" &

                "--AaB03x--\r\n"
            
            form = newAsyncHttpForm("/home/king/tmp")

            (fields, files) = await form.parseAsync("multipart/form-data; boundary=AaB03x", data)

        assert fields["username"]         == newJString("Tom")
        echo   files["upload"][0]["path"] #  "/home/king/tmp/55cdf98a0fbeb30400000000.txt"
        assert files["upload"][0]["size"] == newJInt(6)
        assert files["upload"][0]["type"] == newJString("text/plain")
        assert files["upload"][0]["name"] == newJString("file1.txt")
        echo   files["upload"][1]["path"] #  "/home/king/tmp/55cdf98a0fbeb30400000001.gif"
        assert files["upload"][1]["size"] == newJInt(12)
        assert files["upload"][1]["type"] == newJString("image/gif")
        assert files["upload"][1]["name"] == newJString("file2.gif")

        poll()

    asyncCheck mainAsync()
    #main()