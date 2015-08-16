import ../httpform, asyncdispatch, asynchttpserver,
       strutils, os, strtabs, json

proc main() =
    var
        server = newAsyncHttpServer()
        form = newAsyncHttpForm(getTempDir(), true)
        html = """
<!Doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
</head>
<body>
<form action="/" method="POST"  enctype="multipart/form-data">
    <input type="text" name="name1"/>
    <input type="file" name="files" multiple/>
    <input type="submit" name="submit"></input>
</form>
</body>
</html>"""

    proc cb(req: Request) {.async.} =
        var (fields, files) = await form.parseAsync(req.headers["Content-Type"], req.body)
        if req.reqMethod.toLower() == "get":
            await req.respond(Http200, html)
        else:
            echo fields
            echo files
            await req.respond(Http200, "OK")
    waitFor server.serve(Port(8000), cb)

main()