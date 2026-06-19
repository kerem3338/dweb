module dweb.server;

import dweb;
import dweb.status;
import dweb.http_parser;
import dweb.session;
import dweb.router;
import dweb.log;

import std.socket;
import std.stdio;
import std.string;
import core.thread;
import core.stdc.signal;
import core.stdc.stdlib : exit;
import std.parallelism : TaskPool, task;
import std.conv : to;

extern(C) void handleSigint(int) nothrow @nogc {
    import core.stdc.stdio : puts;
    puts("\nServer stopped.");
    exit(0);
}

struct ServerConfig {
    ushort port = 8080;
    string addr = "127.0.0.1";
    size_t workerThreads = 16;
}

class Server {
    ServerConfig config;
    bool isRunning;
    SessionStore sessionStore;
    Router router;
    Logger logger;

    alias ErrorHandler = void delegate(ref Context ctx);
    private ErrorHandler[ushort] _errorHandlers;
    private ErrorHandler _globalErrorHandler;

    this(string addr = "127.0.0.1", ushort port = 8080) {
        config.addr = addr;
        config.port = port;
        sessionStore = new SessionStore();
        router = new Router();
        logger = new Logger("Server");
    }

    void before(BeforeHandler h) { router.before(h); }
    void after(AfterHandler h) { router.after(h); }

    void error(ushort code, ErrorHandler handler) {
        _errorHandlers[code] = handler;
    }

    void error(ErrorHandler handler) {
        _globalErrorHandler = handler;
    }

    import std.traits : EnumMembers;
    static foreach (m; EnumMembers!RequestMethod) {
        mixin("void " ~ __traits(identifier, m) ~ "(string path, RouteHandler handler) { router." ~ __traits(identifier, m) ~ "(path, handler); }");
        mixin("void " ~ __traits(identifier, m) ~ "(string name, string path, RouteHandler handler) { router." ~ __traits(identifier, m) ~ "(name, path, handler); }");
    }

    void route(string name, string path, RequestMethod[] methods, RouteHandler handler) { router.route(name, path, methods, handler); }
    void route(string path, RequestMethod[] methods, RouteHandler handler) { router.route(path, methods, handler); }
    void route(string name, string path, RouteHandler handler) { router.route(name, path, handler); }
    void route(string path, RouteHandler handler) { router.route(path, handler); }

    void listen() {
        isRunning = true;

        signal(SIGINT, &handleSigint);

        auto server = new TcpSocket();
        server.bind(new InternetAddress(config.addr, config.port));
        server.listen(50);

        auto pool = new TaskPool(config.workerThreads);
        scope(exit) pool.finish(true);

        logger.info("Server running on http://" ~ config.addr ~ ":" ~ to!string(config.port));
        logger.info("Press Ctrl+C to stop.");

        while (isRunning) {
            auto sock = server.accept();
            pool.put(task(&this.handleClient, sock));
        }

        server.close();
        logger.info("Server stopped.");
    }

    private void handleClient(Socket sock)
    {
        scope(exit) sock.close();

        Context ctx;
        bool ctxInitialized = false;

        try {
            auto client = new Client(sock);

            char[8192] buffer;
            auto received = sock.receive(buffer);

            if (received <= 0)
                return;

            string raw = buffer[0 .. received].idup;

            Request req = parseRequest(raw);
            client.request = req;

            ctx = Context(client, req);
            ctx.router = this.router;
            ctxInitialized = true;

            parseCookies(ctx);
            buildCookies(ctx);

            string sid = ctx.cookies.get("session_id", Cookie.init).value;
            string originalSid = sid;

            ctx.session = sessionStore.getOrCreate(sid);

            if (ctx.session.id != originalSid) {
                ctx.setCookie(Cookie("session_id", ctx.session.id, "/", "", -1, true, false));
            }

            logger.info(client.ip ~ " " ~ to!string(req.method) ~ " " ~ req.path);

            router.handle(ctx);

            if (ctx.response.status.code >= 400) {
                handleError(ctx);
            }

            applyCookies(ctx, ctx.response);
            sock.send(ctx.response.serialize());

        } catch (Exception e) {
            logger.error("error: " ~ e.msg);

            if (ctxInitialized) {
                ctx.error = e;
                if (ctx.response.status.code < 400) {
                    ctx.response.status = Status(HttpStatus.internalServerError);
                }
                
                try {
                    handleError(ctx);
                    applyCookies(ctx, ctx.response);
                    sock.send(ctx.response.serialize());
                    return;
                } catch (Exception ex) {
                    logger.error("Error handler failed: " ~ ex.msg);
                }
            }

            try {
                Response res;
                res.status = Status(HttpStatus.internalServerError);
                res.body = "Internal Server Error";
                sock.send(res.serialize());
            } catch (Exception ex) {}
        }
    }

    private void handleError(ref Context ctx) {
        auto code = ctx.response.status.code;
        if (code in _errorHandlers) {
            _errorHandlers[code](ctx);
        } else if (_globalErrorHandler !is null) {
            _globalErrorHandler(ctx);
        }
    }

    void stop() {
        isRunning = false;
        logger.info("Stopped");
    }

    string getFullAddr() {
        return config.addr ~ ":" ~ config.port.to!string;
    }
}