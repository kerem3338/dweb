module dweb.context;

import dweb.client;
import dweb.request;
import dweb.response;
import dweb.cookie;
import dweb.session;
import dweb.router;
import dweb.views;
import dweb.status;

struct Context {
    string[string] cookieMap;
    Cookie[string] cookies;

    Session session;
    Router router;

    Client client;
    Request request;
    Response response;
    
    Exception error;

    this(Client client, Request request) {
        this.client = client;
        this.request = request;
        this.response = Response.init;
    }

    string urlFor(string name, string[string] params = null) {
        if (router is null) return "";
        return router.urlFor(name, params);
    }

    void render(string viewPath, string[string] data = null, string contentType = "text/html") {
        Router r = this.router;
        auto urlForFn = new UrlForFunction((string name, string[string] params) {
            if (r is null) return "";
            return r.urlFor(name, params);
        });

        string html = renderFile(viewPath, data is null ? (string[string]).init : data, [urlForFn]);
        response.headers["Content-Type"] = contentType ~ "; charset=utf-8";
        response.body = html;
    }
}

void parseCookies(ref Context ctx) {
    auto header = ctx.request.header("Cookie");
    if (!header.length) return;
    
    import std.array : split;
    import std.string : strip;
    
    foreach (pair; header.split(";")) {
        auto kv = pair.split("=");
        if (kv.length == 2) {
            ctx.cookieMap[kv[0].strip] = kv[1].strip;
        }
    }
}

void buildCookies(ref Context ctx)
{
    foreach (name, value; ctx.cookieMap)
    {
        ctx.cookies[name] = Cookie(name, value);
    }
}

void setCookie(ref Context ctx, Cookie c)
{
    ctx.cookies[c.name] = c;
}

void applyCookies(ref Context ctx, ref Response res)
{
    bool first = true;
    string setCookieHeader;
    foreach (c; ctx.cookies)
    {
        if (!first) setCookieHeader ~= "\r\nSet-Cookie: ";
        setCookieHeader ~= serializeCookie(c);
        first = false;
    }
    if (!first)
        res.headers["Set-Cookie"] = setCookieHeader;
}