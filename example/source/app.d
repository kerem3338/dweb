import dweb;

import std.stdio;
import std.format;

void main()
{
    auto app = new Server("127.0.0.1", 8080);

    app.before((ref Context ctx) {
        app.logger.info(format("Before Hook: %s %s", ctx.request.method, ctx.request.path));
        
        return true;
    });

    app.error(500, (ref Context ctx) {
        ctx.response.status = Status(HttpStatus.internalServerError);
        ctx.response.body = "<h1>"~reasonPhrase(ctx.response.status.code)~"</h1><pre>"~ctx.error.msg~"</pre><hr>Dweb example application running on "~app.getFullAddr();
        ctx.response.setContentType("text/html");
    });

    app.route("error_500", "/500", (ref Context ctx) {
        throw new Exception("This is a error");
    });

    app.route("user_profile", "/user/:id", (ref Context ctx) {
        ctx.response.status = Status(HttpStatus.ok);
        string id = ctx.request.params.get("id", "unknown");

        ctx.render("views/profile.html.tpl", [
            "id":       id,
            "name":     "User #" ~ id,
            "is_admin": (id == "99") ? "true" : "false"
        ]);
    });

    app.route("index", "/", (ref Context ctx) {
        ctx.response.setContentType("text/html");
        ctx.response.status = Status(HttpStatus.ok);

        ctx.render("views/index.html.tpl");
    });

    app.route("json", "/json", (ref Context ctx) {
        ctx.response.status = Status(HttpStatus.ok);
        ctx.response.headers["Content-Type"] = "application/json";
        ctx.response.body = `{"message":"hello world"}`;
    });

    app.listen();
}