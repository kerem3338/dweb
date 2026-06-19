module dweb.router;

import dweb.context;
import dweb.request;
import std.regex;
import std.string;
import std.array;

alias BeforeHandler = bool delegate(ref Context ctx);
alias AfterHandler = void delegate(ref Context ctx);
alias RouteHandler = void delegate(ref Context ctx);

struct Route {
    string name;
    RequestMethod method;
    string pathTemplate;
    Regex!char regex;
    string[] paramNames;
    RouteHandler handler;
}

class Router {
    private Route[] routes;
    private BeforeHandler[] beforeHooks;
    private AfterHandler[] afterHooks;

    void before(BeforeHandler h) {
        beforeHooks ~= h;
    }

    void after(AfterHandler h) {
        afterHooks ~= h;
    }

    void addRoute(string name, RequestMethod method, string path, RouteHandler handler) {
        if (name.length > 0) {
            foreach (ref route; routes) {
                if (route.name == name && route.pathTemplate != path) {
                    throw new Exception("Route name '" ~ name ~ "' is already used by another path.");
                }
            }
        }

        string regexStr = "^";
        string[] pNames;

        auto parts = path.split("/");
        foreach (i, part; parts) {
            if (i > 0) regexStr ~= "/";
            if (part.startsWith(":")) {
                pNames ~= part[1..$];
                regexStr ~= "([^/]+)";
            } else {
                regexStr ~= part;
            }
        }
        regexStr ~= "$";

        routes ~= Route(name, method, path, regex(regexStr), pNames, handler);
    }

    void addRoute(RequestMethod method, string path, RouteHandler handler) {
        addRoute("", method, path, handler);
    }

    string urlFor(string name, string[string] params = null) {
        foreach (ref route; routes) {
            if (route.name == name) {
                string url = route.pathTemplate;
                foreach (k, v; params) {
                    url = url.replace(":" ~ k, v);
                }
                return url;
            }
        }
        return "";
    }

    import std.traits : EnumMembers;
    static foreach (m; EnumMembers!RequestMethod) {
        mixin("void " ~ __traits(identifier, m) ~ "(string path, RouteHandler handler) { addRoute(RequestMethod." ~ __traits(identifier, m) ~ ", path, handler); }");
        mixin("void " ~ __traits(identifier, m) ~ "(string name, string path, RouteHandler handler) { addRoute(name, RequestMethod." ~ __traits(identifier, m) ~ ", path, handler); }");
    }

    void route(string name, string path, RequestMethod[] methods, RouteHandler handler) {
        foreach (m; methods) {
            addRoute(name, m, path, handler);
        }
    }

    void route(string path, RequestMethod[] methods, RouteHandler handler) {
        route("", path, methods, handler);
    }

    void route(string name, string path, RouteHandler handler) {
        addRoute(name, RequestMethod.get, path, handler);
    }

    void route(string path, RouteHandler handler) {
        route("", path, handler);
    }

    void handle(ref Context ctx) {
        // before
        foreach (hook; beforeHooks) {
            if (!hook(ctx)) return;
        }

        bool matched = false;
        foreach (ref route; routes) {
            if (route.method == ctx.request.method) {
                auto m = matchFirst(ctx.request.path, route.regex);
                if (m) {
                    matched = true;

                    foreach (i, pName; route.paramNames) {
                        ctx.request.params[pName] = m[i + 1].idup;
                    }
                    route.handler(ctx);
                    break;
                }
            }
        }

        if (!matched) {
            import dweb.status;
            ctx.response.status = Status(HttpStatus.notFound);
            ctx.response.body = "<b>" ~ reasonPhrase(ctx.response.status.code) ~ "</b>";
        }

        // after
        foreach (hook; afterHooks) {
            hook(ctx);
        }
    }
}
