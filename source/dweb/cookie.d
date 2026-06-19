module dweb.cookie;

import std.string;
import std.conv;

struct Cookie
{
    string name;
    string value;

    string path = "/";
    string domain;

    long maxAge = -1; // -1 = session cookie

    bool httpOnly = true;
    bool secure = false;
}

string serializeCookie(Cookie c)
{
    string s = c.name ~ "=" ~ c.value;

    if (c.path.length) s ~= "; Path=" ~ c.path;
    if (c.domain.length) s ~= "; Domain=" ~ c.domain;
    if (c.maxAge >= 0) s ~= "; Max-Age=" ~ c.maxAge.to!string;
    if (c.httpOnly) s ~= "; HttpOnly";
    if (c.secure) s ~= "; Secure";

    return s;
}