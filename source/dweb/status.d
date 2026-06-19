module dweb.status;

enum HttpStatus : ushort {
    continue_            = 100,

    ok                   = 200,
    created              = 201,
    noContent            = 204,

    movedPermanently     = 301,
    found                = 302,

    badRequest           = 400,
    unauthorized         = 401,
    forbidden            = 403,
    notFound             = 404,

    internalServerError  = 500,
    notImplemented       = 501,
    serviceUnavailable   = 503
}

struct Status {
    ushort code;
    string reason;

    this(HttpStatus s) {
        code = cast(ushort) s;
        reason = reasonPhrase(s);
    }
}

string reasonPhrase(HttpStatus code) {
    final switch (code) {
        case HttpStatus.continue_:           return "Continue";

        case HttpStatus.ok:                  return "OK";
        case HttpStatus.created:             return "Created";
        case HttpStatus.noContent:           return "No Content";

        case HttpStatus.movedPermanently:    return "Moved Permanently";
        case HttpStatus.found:               return "Found";

        case HttpStatus.badRequest:         return "Bad Request";
        case HttpStatus.unauthorized:       return "Unauthorized";
        case HttpStatus.forbidden:          return "Forbidden";
        case HttpStatus.notFound:           return "Not Found";

        case HttpStatus.internalServerError: return "Internal Server Error";
        case HttpStatus.notImplemented:      return "Not Implemented";
        case HttpStatus.serviceUnavailable:  return "Service Unavailable";
    }
}

string reasonPhrase(ushort code) {
    return reasonPhrase(cast(HttpStatus) code);
}

bool isSuccess(HttpStatus code) {
    auto c = cast(ushort) code;
    return c >= 200 && c < 300;
}

bool isClientError(HttpStatus code) {
    auto c = cast(ushort) code;
    return c >= 400 && c < 500;
}

bool isServerError(HttpStatus code) {
    auto c = cast(ushort) code;
    return c >= 500 && c < 600;
}