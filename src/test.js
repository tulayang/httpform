function server() {
    var server = require('http').createServer();
    var form = new require('formidable').IncomingForm();

    form.keepExtensions = true;
    form.uploadDir      = '/home/king/tmp';
    form.multiples      = true;
    form.maxFieldsSize  = 1024; 

    server.on('request', function (req, res) {
        if (req.method.toLowerCase() === 'get') {
            res.writeHead(200, {'content-type': 'text/html'});
            res.end(
                require('fs').readFileSync(__dirname + '/index.html', 'utf8')
            );
            return;
        }

        form.parse(req, function (err, fields, files) {
            console.log('fields:', fields);
            console.log('files:', files);
            res.end();
        });
    });

    server.listen(10001);
}

function clientJson() {
/*
    fields: { a: '100', b: [ { a: 1, b: 2 } ] }
    files: {}
*/

    var data = new Buffer('{"a":"100", "b":[{"a":1, "b":2}]}');
    var client = require('http').request({
        hostname: '127.0.0.1',
        port: '10001',
        method: 'post',
        url: '/',
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': data.length
        }
    });
    client.write(data);
    client.end();
}

function clientUrlencoded() {
/*
    fields: { a: '100', b: '200' }
    files: {}
*/
    var data = new Buffer('a=100&b=200');
    var client = require('http').request({
        hostname: '127.0.0.1',
        port: '10001',
        method: 'post',
        url: '/',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Content-Length': data.length
        }
    });
    client.write(data);
    client.end();
}

function clientOctetStream() {
/*
    fields: {}
    files: { file: 
       { domain: null,
         _events: {},
         _maxListeners: undefined,
         size: 5,
         path: '/home/king/tmp/upload_8cb03e5bf77d0adbc7445217c7da24ce',
         name: undefined,
         type: 'application/octet-stream',
         hash: null,
         lastModifiedDate: Thu Aug 13 2015 17:31:03 GMT+0800 (CST),
         _writeStream: 
          { _writableState: [Object],
            writable: true,
            domain: null,
            _events: {},
            _maxListeners: undefined,
            path: '/home/king/tmp/upload_8cb03e5bf77d0adbc7445217c7da24ce',
            fd: null,
            flags: 'w',
            mode: 438,
            start: undefined,
            pos: undefined,
            bytesWritten: 5,
            closed: true } } }      
*/
    var data = new Buffer('000000');
    var client = require('http').request({
        hostname: '127.0.0.1',
        port: '10001',
        method: 'post',
        url: '/',
        headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Length': data.length
        }
    });
    client.write(data);
    client.end();
}

function clientMultipart() {
    var data = new Buffer(
        '--AaB03x\r\n' +
        'Content-Disposition: form-data; name="name1"\r\n\r\n' +
        'aaa\r\n' +

        '--AaB03x\r\n' +
        'Content-Disposition: form-data; name="a"; filename="file1.txt"\r\n' +
        'Content-Type: text/plain\r\n\r\n' +
        '01010101\r\n' +

        '--AaB03x--\r\n'
    );
    var client = require('http').request({
        hostname: '127.0.0.1',
        port: '10001',
        method: 'post',
        url: '/',
        headers: {
            'Content-Type': 'multipart/form-data; boundary=AaB03x',
            'Content-Length': data.length
        }
    });
    client.write(data);
    client.end();
}

function clientMultipartMore() {
/*
    fields: { aaa: 'aaa' }
    files: { files: 
       [ { domain: null,
           _events: {},
           _maxListeners: undefined,
           size: 6,
           path: '/home/king/tmp/upload_511efe5e0a234424cf890bc7ca7fc397.txt',
           name: 'a.txt',
           type: null,
           hash: null,
           lastModifiedDate: Thu Aug 13 2015 17:26:03 GMT+0800 (CST),
           _writeStream: [Object] },
         { domain: null,
           _events: {},
           _maxListeners: undefined,
           size: 6,
           path: '/home/king/tmp/upload_1d46f6d97e438d05f2b5bdcfdd32fd3d.txt',
           name: 'c.txt',
           type: 'image/gif',
           hash: null,
           lastModifiedDate: Thu Aug 13 2015 17:26:03 GMT+0800 (CST),
           _writeStream: [Object] },
         { domain: null,
           _events: {},
           _maxListeners: undefined,
           size: 34,
           path: '/home/king/tmp/upload_64e212f3e99d446369bb5c5a3aecf026.txt',
           name: 'b.txt',
           type: null,
           hash: null,
           lastModifiedDate: Thu Aug 13 2015 17:26:03 GMT+0800 (CST),
           _writeStream: [Object] } ] }
*/
    var data = new Buffer(
        '--AaB03x\r\n' +
        'Content-Disposition: form-data; name="aaa"\r\n\r\n' +
        'aaa\r\n' +

        '--AaB03x\r\n' +
        'Content-Disposition: form-data; name="a"; filename="a.txt"\r\n\r\n' + 
        '000000\r\n' +

        '--AaB03x\r\n' +
        'Content-Disposition: form-data; name="a"; filename="b.txt"\r\n' + 
        'Content-Type: text/plain\r\n\r\n' + 
        '000000\r\n' +

        '--AaB03x\r\n' +
        'Content-Disposition: form-data; name=c; filename="c.txt"\r\n' + 
        'Content-Type: image/gif\r\n' + 
        'Content-Transfer-Encoding: base64\r\n\r\n' + // binary 7bit 8bit | base64
        '01010101\r\n' +
        
        '--AaB03x--\r\n'
    );
    var client = require('http').request({
        hostname: '127.0.0.1',
        port: '10001',
        method: 'post',
        url: '/',
        headers: {
            'Content-Type': 'multipart/form-data; boundary=AaB03x',
            'Content-Length': data.length
        }
    });
    client.write(data);
    client.end();
}

server();
clientMultipartMore();
