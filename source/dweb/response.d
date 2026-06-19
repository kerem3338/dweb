module dweb.response;

import dweb.status;
import std.conv;

struct Response {
    Status status;
    string[string] headers;
    string body;

    string serialize() const {
        string result;

        result ~= "HTTP/1.1 ";
        result ~= to!string(status.code);
        result ~= " ";
        result ~= status.reason;
        result ~= "\r\n";

        foreach (key, value; headers)
            result ~= key ~ ": " ~ value ~ "\r\n";

        result ~= "\r\n";

        result ~= body;

        return result;
    }

    void setBody(string body, bool setContentLength = true) {
        this.body = body;
        if (setContentLength) headers["Content-Length"] = to!string(body.length);
    }
    
    void setContentType(string contentType) {
        headers["Content-Type"] = contentType;
    }
}