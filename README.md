HttpForm, The Http Request Form Parser
==========================================

This module was developed for submit form by http protocol, upload and encoding images and videos.

Example
--------

Upload files with **HTML5 `<form>`**:

```nim
import httpform, asyncdispatch, asynchttpserver,
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
    <input type="submit"></input>
</form>
</body>
</html>"""

    proc cb(req: Request) {.async.} =
        var (fields, files) = await form.parseAsync(req.headers["Content-Type"], req.body)
        if req.reqMethod.toLower() == "get":
            await req.respond(Http200, html)
        else:
	    # retrieve sent field and files
	    echo fields["name"] 
	    echo files["upload"][0]["path"] 
	    echo files["upload"][0]["size"] 
	    echo files["upload"][0]["type"]
	    echo files["upload"][0]["name"] 

            await req.respond(Http200, "hello")
    waitFor server.serve(Port(8000), cb)

main()
```

Usage
-------

`$ nimble init` make a .nimble file, and edit:

```
[Package]
name          = "app"
version       = "0.1.0"
author        = "Me"
description   = "My app"
license       = "MIT"

[Deps]
Requires: "nim >= 0.11.0, httpform >= 0.1.0"
```

then you can import **httpform**:

```
import httpform

// TODO
```

API
----

```
FormError = object of Exception
```

raised for invalid content-type or request body.

```
HttpForm = ref object
    tmp: string
    keepExtname: bool
```

form parser. 

```
AsyncHttpForm = HttpForm
```

asynchronous form parser.

```
proc newHttpForm(tmp: string, keepExtname = true): HttpForm
```

creates a new form parser. `tmp` should be set, which will save the uploaded temporary file. If `keepExtname` is true, the extname will be reserved.

```
proc newAsyncHttpForm*(tmp: string, keepExtname = true): AsyncHttpForm
```

creates a new asynchronous form parser.

```
proc parse(x: HttpForm, contentType: string, body: string):
          tuple[fields: JsonNode, files: JsonNode]
          {.tags: [WriteIOEffect, ReadIOEffect].}
```

parse http request body.

```
proc parseAsync(x: AsyncHttpForm, contentType: string, body: string):
               Future[tuple[fields: JsonNode, files: JsonNode]]
               {.async, tags: [RootEffect, WriteIOEffect, ReadIOEffect].}
```

asynchronous parse http request body.
