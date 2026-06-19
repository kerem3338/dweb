module dweb.http_parser;

import dweb.request;
import std.string;
import std.array;

Request parseRequest(string raw) {
    Request req;

    auto lines = raw.split("\r\n");

    if (lines.length == 0)
        return req;

    // request line
    auto parts = lines[0].split(" ");

    if (parts.length >= 2) {
        req.method = toMethod(parts[0]);
        req.path = parts[1];
    }

    // headers
    size_t i = 1;

    for (; i < lines.length; i++) {
        if (lines[i].length == 0)
            break;

        auto h = lines[i].split(": ");

        if (h.length == 2)
            req.headers[h[0]] = h[1];
    }

    // body
    string body;

    for (size_t j = i + 1; j < lines.length; j++) {
        body ~= lines[j];
        if (j != lines.length - 1)
            body ~= "\n";
    }

    req.content = cast(ubyte[]) body;

    return req;
}

RequestMethod toMethod(string m) {
    final switch (m) {
        case "GET":     return RequestMethod.get;
        case "POST":    return RequestMethod.post;
        case "PUT":     return RequestMethod.put;
        case "PATCH":   return RequestMethod.patch;
        case "DELETE":  return RequestMethod._delete;
        case "HEAD":    return RequestMethod.head;
        case "OPTIONS": return RequestMethod.options;
        case "CONNECT": return RequestMethod.connect;
    }
}