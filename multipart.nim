import strutils, os, oids, base64, asyncfile, asyncdispatch, json

include "incl.nim"

type
    MultipartState = enum
        msBeginTk, msEndTk, msDisposition, msContent
    Multipart = ref object
        beginTk, endTk, body: string
        length, head, tail: int
        state: MultipartState
        disposition, name, filename, ctype, encoding: string
        tmp:string
        keepExtname: bool

proc newMultipart(body, boundary: string, tmp:string, keepExtname: bool): Multipart =
    new(result)
    result.head = -1
    result.tail = -1
    result.state = msBeginTk
    result.body = body
    result.length = body.len()
    result.beginTk = "--" & boundary & "\r\n"
    result.endTk = "--" & boundary & "--\r\n"
    result.tmp = tmp
    result.keepExtname = keepExtname

proc moveLine(x: Multipart) = 
    if x.tail < x.length:
        x.tail.inc()
        x.head = x.tail
        while true:
            if x.tail == x.length:
                break
            if x.body[x.tail] == '\13' and 
               x.tail + 1 < x.length   and 
               x.body[x.tail + 1] == '\10':  # \r\n
                x.tail.inc()
                break
            x.tail.inc()

proc moveParagraph(x: Multipart) =
    if x.tail < x.length:
        x.tail.inc()
        x.head = x.tail
        while true:
            if x.tail == x.length:
                break
            if x.body[x.tail] == '\13'     and 
               x.tail + 3 < x.length       and 
               x.body[x.tail] == '\13'     and 
               x.body[x.tail + 1] == '\10' and 
               x.body[x.tail + 2] == '\13' and 
               x.body[x.tail + 3] == '\10':     # \r\n\r\n
                x.tail.inc(3)
                break
            x.tail.inc() 

proc pickBeginTk(x: Multipart) =
    # echo ">>> beginTk"
    x.moveLine()
    if x.tail == x.length or x.body[x.head..x.tail] != x.beginTk:
        raise newException(FormError, "bad multipart boundary")
    x.state = msDisposition

proc pickDisposition(x: Multipart) = 
    # echo ">>> disosition"
    x.moveParagraph()
    if x.tail == x.length or x.tail - 4 < x.head:
        raise newException(FormError, "bad multipart disposition")

    var 
        dispItems: seq[string]
        i, h: int

    x.disposition = nil
    x.name = nil 
    x.filename = nil
    x.ctype = nil
    x.encoding = nil

    for line in x.body[x.head..x.tail-4].split("\r\n"):
        i = line.find(": ")
        h = line.high()
        if i > 0 and i < h-1:
            case line[0..i-1].toLower()
            of "content-disposition":
                dispItems = line[i+2..h].split("; ")
                if dispItems[0] == "form-data": # disp?
                    x.disposition = dispItems[0]
                    for s in dispItems:
                        i = s.find('=')
                        h = s.high()
                        if i > 0:
                            case s[0..i-1].toLower()
                            of "name":
                                x.name = if i < h: s[i+1..h].delQuote() else: ""
                            of "filename":
                                x.filename = if i < h: s[i+1..h].delQuote() else: ""
                            else:
                                discard
            of "content-type":
                x.ctype = line[i+2..h]
            of "content-transfer-Encoding":
                x.encoding = line[i+2..h]
            else:
                discard

    if x.disposition != "form-data":
        raise newException(FormError, "bad multipart disposition")

    # echo x.disposition
    # echo x.ctype
    # echo x.name
    # echo x.filename

    x.state = msContent

template doWrite(content: string) =
    var 
        path: string
    if not x.name.isNil():
        # echo "---", repr content
        # echo "---"
        if x.filename.isNil(): 
            result.fields[x.name] = newJString(content)
        else:
            path = joinPath(x.tmp, if x.keepExtname: $genOid() & splitFile(x.filename).ext
                                   else: $genOid())
            case x.encoding
            of nil, "binary", "7bit", "8bit": writeFile(path, content)  
            of "base64": writeFile(path, decode(content))
            else: raise newException(FormError, "unknow transfer encoding")  
            if not result.files.hasKey(x.name): result.files[x.name] = newJArray()
            result.files[x.name].add(newFile(path, content.len(), x.ctype, x.filename)) 

template pickContent(x: Multipart) = 
    # echo ">>> content"
    var 
        begin = x.tail + 1
        finish: int
        text: string
    while true:
        x.moveLine()
        if x.tail == x.length:
            raise newException(FormError, "bad multipart content")
        text = x.body[x.head..x.tail]
        if text == x.beginTk:
            finish = x.tail - x.beginTk.len() - 2
            if finish >= begin:
                doWrite(x.body[begin..finish])
            x.state = msDisposition
            break
        if text == x.endTk:
            finish = x.tail - x.endTk.len() - 2
            if finish >= begin:
                doWrite(x.body[begin..finish])
            x.state = msEndTk
            break

proc parseMultipart(body: string, boundary: string, tmp: string, keepExtname: bool):
                   tuple[fields: JsonNode, files: JsonNode]
                   {.tags: [WriteIOEffect].} =
    var x = newMultipart(body, boundary, tmp, keepExtname)
    result.fields = newJObject()
    result.files = newJObject()
    while true:
        case x.state
        of msBeginTk: x.pickBeginTk()
        of msDisposition: x.pickDisposition()
        of msContent: x.pickContent()
        of msEndTk: break
        else: discard

proc writeFileAsync(path: string, content: string) {.async.} =
    var file = openAsync(path, fmWrite)
    await file.write(content)
    file.close()

proc doWriteAsync(x: Multipart, content: string, 
                  r: tuple[fields: JsonNode, files: JsonNode]) {.async.} =
    var 
        path: string
    if not x.name.isNil():
        # echo "---", repr content
        # echo "---"
        if x.filename.isNil(): 
            r.fields[x.name] = newJString(content)
        else:
            path = joinPath(x.tmp, if x.keepExtname: $genOid() & splitFile(x.filename).ext
                                   else: $genOid())
            case x.encoding
            of nil, "binary", "7bit", "8bit": await writeFileAsync(path, content)  
            of "base64": await writeFileAsync(path, decode(content))
            else: raise newException(FormError, "unknow transfer encoding")  
            if not r.files.hasKey(x.name): r.files[x.name] = newJArray()
            r.files[x.name].add(newFile(path, content.len(), x.ctype, x.filename)) 

proc pickContentAsync(x: Multipart, r: tuple[fields: JsonNode, files: JsonNode]) {.async.} = 
    # echo ">>> content"
    var 
        begin = x.tail + 1
        finish: int
        text: string
    while true:
        x.moveLine()
        if x.tail == x.length:
            raise newException(FormError, "bad multipart content")
        text = x.body[x.head..x.tail]
        if text == x.beginTk:
            finish = x.tail - x.beginTk.len() - 2
            if finish >= begin:
                await x.doWriteAsync(x.body[begin..finish], r)
            x.state = msDisposition
            break
        if text == x.endTk:
            finish = x.tail - x.endTk.len() - 2
            if finish >= begin:
                await x.doWriteAsync(x.body[begin..finish], r)
            x.state = msEndTk
            break

proc parseMultipartAsync(body: string, boundary: string, tmp: string, keepExtname: bool):
                        Future[tuple[fields: JsonNode, files: JsonNode]]
                        {.async, tags: [RootEffect, WriteIOEffect, ReadIOEffect].} =  
    var x = newMultipart(body, boundary, tmp, keepExtname)
    result.fields = newJObject()
    result.files = newJObject()
    while true:
        case x.state
        of msBeginTk: x.pickBeginTk()
        of msDisposition: x.pickDisposition()
        of msContent: await x.pickContentAsync(result)
        of msEndTk: break
        else: discard
