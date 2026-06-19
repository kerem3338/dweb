# dweb

A simple, expressive web framework for the [D programming language](https://dlang.org/), inspired by Flask.

## Features

- **Routing** — Named routes with URL parameters (`:param`), per-method or multi-method handlers
- **Middleware** — `before` / `after` hooks on every request
- **Template rendering** — Powered by [Z-Template](https://github.com/kerem3338/dtools) with `url_for()` support inside templates
- **Sessions** — In-memory session store with automatic TTL and UUID-based session IDs
- **Cookies** — Parse, build, and set cookies with full attribute support
- **Error handling** — Register custom handlers per status code or a global fallback
- **Logging** — Structured logger with console, file, and in-memory handlers
- **Thread pool** — Multi-threaded request handling via `std.parallelism.TaskPool`

---

## Quick Start

```d
import dweb;

void main()
{
    auto app = new Server("127.0.0.1", 8080);

    // Middleware
    app.before((ref Context ctx) {
        // Return false to short-circuit the request
        return true;
    });

    // Named route with URL parameter
    app.get("user_profile", "/user/:id", (ref Context ctx) {
        ctx.response.status = Status(HttpStatus.ok);
        string id = ctx.request.params.get("id", "unknown");
        ctx.render("views/profile.html", ["id": id, "name": "User #" ~ id]);
    });

    // Plain text response
    app.get("home", "/", (ref Context ctx) {
        ctx.response.status = Status(HttpStatus.ok);
        ctx.response.headers["Content-Type"] = "text/plain";
        ctx.response.body = "Hello, world!";
    });

    // JSON response
    app.get("/api/hello", (ref Context ctx) {
        ctx.response.status = Status(HttpStatus.ok);
        ctx.response.headers["Content-Type"] = "application/json";
        ctx.response.body = `{"message": "hello"}`;
    });

    // Custom error pages
    app.error(500, (ref Context ctx) {
        ctx.response.body = "<h1>Something went wrong</h1><p>" ~ ctx.error.msg ~ "</p>";
    });

    app.error(404, (ref Context ctx) {
        ctx.response.body = "<h1>Page not found</h1>";
    });

    app.listen();
}
```

---

## Routing

```d
// HTTP method shortcuts
app.get("/path", handler);
app.post("/path", handler);
app.put("/path", handler);
app.delete_("/path", handler);

// Named route (usable with url_for in templates)
app.get("route_name", "/path", handler);

// Multi-method route
app.route("/path", [RequestMethod.get, RequestMethod.post], handler);

// URL parameters — accessed via ctx.request.params
app.get("/user/:id/post/:slug", (ref Context ctx) {
    string id   = ctx.request.params["id"];
    string slug = ctx.request.params["slug"];
});
```

---

## Templates

Templates use the Z-Template engine. The `url_for` function is available in every template automatically.

```html
<!-- views/profile.html -->
<a href="{{ url_for("home") }}">Home</a>
<p>Hello, {{ name }}!</p>

{% if (is_admin == "true") %}
<span>Admin</span>
{% endif %}
```

```d
ctx.render("views/profile.html", [
    "name":     "Alice",
    "is_admin": "false"
]);
```

If a template error occurs (unknown function, missing file, syntax error, etc.), the request is automatically routed to your `500` error handler with the full error detail in `ctx.error`.

---

## Sessions

Sessions are created automatically per request and stored in memory.

```d
// Read
string username = ctx.session.data.get("username", "");

// Write
ctx.session.data["username"] = "alice";
```

Sessions expire after 1 hour by default (TTL refreshes on each access).

---

## Cookies

```d
// Read parsed cookies
string token = ctx.cookieMap.get("token", "");

// Set a cookie
ctx.setCookie(Cookie("token", "abc123", "/", "", 3600, true, true));
```

---

## Logging

```d
import dweb.log;

auto logger = new Logger("MyApp");
logger.addHandler(new FileHandler("app.log")); // optional: also log to file

logger.info("Server started");
logger.warn("Something looks off");
logger.error("Unhandled exception: " ~ e.msg);
```

The `Server` class has a built-in `logger` field (named `"Server"`) that handles all request and error logs.

---

## Installation

Add to your `dub.json`:

```json
"dependencies": {
    "dweb": { "path": "../dweb" }
}
```

See [DEV_NOTICE.md](DEV_NOTICE.md) for instructions on setting up the Z-Template vendor dependency via envman.

---

## License

MIT © 2026 zoda
[LICENSE](LICENSE)