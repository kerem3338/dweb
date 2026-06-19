module dweb.request;

import dweb.cookie;

enum RequestMethod {
    get,
    post,
    put,
    patch,
    _delete,
    head,
    options,
    connect
}

struct Request {
    RequestMethod method;
    string path;
    string[string] headers;
    string[string] params;
    ubyte[] content;
    Cookie[string] cookies;

    string header(string key, string def = "") const {
        auto p = key in headers;
        return p ? *p : def;
    }

    string contentAsString() const {
        return cast(string) content;
    }
}