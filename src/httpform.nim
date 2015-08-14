import strutils, json, os, oids, base64, asyncfile

type
    FormError = object of Exception

proc newFile(path: string, size: int, ctype: string, filename: string): JsonNode = 
    result = newJObject()
    result["path"] = newJString(path)
    result["size"] = newJInt(size)
    result["type"] = newJString(ctype)
    result["name"] = newJString(filename)

proc parseOctetStream(str: string, tmp: string): 
                     tuple[fields: JsonNode, files: JsonNode]
                     {.raises: [Exception, IOError], tags: [WriteIOEffect].} =
    var path = joinPath(tmp, $genOid())
    writeFile(path, str)
    var options = newJArray()
    options.add(newFile(path, str.len(), "", "application/octet-stream"))
    var files = newJObject()
    files[nil] = options
    result = (fields: nil, files: files)

proc parseMultipart(boundry: string, str: string, tmp: string, keepExtname = true):
                   tuple[fields: JsonNode, files: JsonNode]
                   {.raises: [Exception, IOError], tags: [WriteIOEffect].} =
    var
        beginTk = "--" & boundry
        endTk = "--" & boundry & "--"
        length = str.len()
        text = ""
        head = 0
        tail = 0
        disposition, name, filename, encoding, ctype: string
        fields, files = newJObject()
        path: string

    proc delQuote(str: string): string =
    # "a" => a
        var length = str.len()
        if str == "\"\"": 
            return ""
        if length < 3: 
            return str
        if str[0] == '\"' and str[length-1] == '\"': 
            return str[1..length-2]
        return str

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
                text = str[head..tail-1]
                head = tail
                return
            if str[tail] == '\13':              # \r
                if tail + 1 < length: 
                    if str[tail + 1] == '\10':  # \n
                        text = str[head..tail-1]
                        tail = tail + 2
                        head = tail
                        return
                else:
                    text = str[head..tail]
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
                text = str[head..tail-1]
                head = tail
                return
            if str[tail] == '\13': 
                if tail + 3 < length:
                    if str[tail] == '\13'     and str[tail + 1] == '\10' and 
                       str[tail + 2] == '\13' and str[tail + 3] == '\10':  # \r\n\r\n
                        text = str[head..tail-1]
                        tail = tail + 4
                        head = tail
                        return
                else:
                    text = str[head..tail+2]
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

    proc compose() {.inline.} =
        if filename.isNil(): 
        # fields
            if not name.isNil():
                fields[name] = newJString(text)
        else: 
        # files
            if not name.isNil():
                path = joinPath(tmp, if keepExtname: $genOid() & splitFile(filename).ext 
                                     else: $genOid())
                if encoding == "base64":
                    text = decode(text)
                writeFile(path, text)
                if not files.hasKey(name):
                    files[name] = newJArray()
                files[name].add(newFile(path, text.len(), ctype, filename)) 

    proc walk() =
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
                compose()
            reset()  
        
    walk()
    result = (fields: fields, files: files)

proc parseHttpForm*(contentType: string, body: string, 
                    tmp: string, keepExtname = true): tuple[fields: JsonNode, files: JsonNode]
                    {.raises: [Exception, IOError, FormError], tags: [WriteIOEffect, ReadIOEffect].} =    
    if not body.isNil() and body.len() > 0:
        if contentType.isNil() or contentType.len() == 0:
            raise newException(FormError, "bad content-type header, no content-type")
        case contentType.toLower()
        of "application/json":
            result = (fields: parseJson(body), files: nil)
        of "application/x-www-form-urlencoded":
            var fields = newJObject()
            var x: seq[string] 
            for it in body.split('&'):
                x = it.split('=')
                case x.len():
                of 0: discard
                of 1: fields[x[0]] = newJNull()
                else: fields[x[0]] = newJString(x[1])
            result = (fields: fields, files: nil)
        of "application/octet-stream":
            result = parseOctetStream(body, tmp)
        else:
            if contentType.toLower().contains("multipart/form-data"):
                # Content-Type': 'multipart/form-data; boundary=AaB03x
                var cs = contentType.split("; ")
                if cs.len() < 2:
                    raise newException(FormError, "bad content-type header, no multipart boundary")
                var bs = cs[1].split("=")
                if bs.len() < 2 or bs[0] != "boundary" or bs[1].len() == 0:
                    raise newException(FormError, "bad content-type header, no multipart boundary")
                result = parseMultipart(bs[1], body, tmp, keepExtname)
            else:
                var fields = newJObject()
                fields[nil] = newJString(body)
                result = (fields: fields, files: nil)

when isMainModule:
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
        
        (fields, files) = parseHttpForm("multipart/form-data; boundary=AaB03x", data, "/home/king/tmp")

    echo fields["username"]             # Tom
    echo files["upload"][0]["path"]     # /home/king/tmp/55cdf98a0fbeb30400000000.txt
    echo files["upload"][0]["size"]     # 6
    echo files["upload"][0]["type"]     # text/plain
    echo files["upload"][0]["name"]     # file1.txt
    echo files["upload"][1]["path"]     # /home/king/tmp/55cdf98a0fbeb30400000001.gif
    echo files["upload"][1]["size"]     # 9
    echo files["upload"][1]["type"]     # image/gif
    echo files["upload"][1]["name"]     # file2.gif