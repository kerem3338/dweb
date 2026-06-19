module dweb.views;

import dweb.tpl : TextTemplate, TemplateFunction, GenerationResult, ErrorReporting, TemplateError, ErrorType;
import std.variant : Variant;
import std.string  : strip, indexOf;
import std.file    : readText, exists;
import std.format  : format;
import std.conv    : to;


class UrlForFunction : TemplateFunction {
    string delegate(string name, string[string] params) resolver;

    this(string delegate(string name, string[string] params) resolver) {
        super("url_for", "Generates a URL for a named route");
        minArgs = 1;
        this.resolver = resolver;
    }

    protected override Variant call(Variant[] args,
                                    ref Variant[string] data,
                                    TextTemplate context) {
        // First arg: route name (strip surrounding quotes if literal string)
        string routeName = context.resolve(args[0], data).coerce!string;

        // Remaining args: "key=value" pairs
        string[string] params;
        foreach (arg; args[1 .. $]) {
            string pair = context.resolve(arg, data).coerce!string;
            auto eq = pair.indexOf('=');
            if (eq != -1)
                params[pair[0 .. eq].strip] = pair[eq + 1 .. $].strip;
        }

        string url = resolver(routeName, params);
        if (url == "") {
            context.reportError(TemplateError(ErrorType.invalidPath, "Route not found for url_for: " ~ routeName, context.loc));
            return Variant("");
        }
        return Variant(url);
    }
}

string renderFile(string filePath,
                  string[string] strData,
                  TemplateFunction[] extraFuncs = null) {
    if (!filePath.exists)
        throw new Exception(format("Template not found: %s", filePath));

    string src;
    try {
        src = readText(filePath);
    } catch (Exception e) {
        throw new Exception(format("Template read error: %s", e.msg));
    }

    Variant[string] data;
    foreach (k, v; strData)
        data[k] = Variant(v);

    auto tpl = new TextTemplate(src);
    tpl.errorReporting = ErrorReporting.failOnError;

    // Disable dangerous features
    tpl.settings.allowStdio     = false;
    tpl.settings.allowFileWrite = false;

    // Register extra functions (url_for, etc.)
    foreach (fn; extraFuncs)
        tpl.registerFunction(fn);

    GenerationResult result = tpl.generate(data);
    if (tpl.errors.length > 0) {
        string[] errs;
        foreach (err; tpl.errors) {
            errs ~= err.asHumaneString();
        }
        import std.array : join;
        throw new Exception("Template errors:\n" ~ errs.join("\n"));
    }
    
    return result.output;
}
