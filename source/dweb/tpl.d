/**
template

template.d:
	Custom text template system.

	The template engine is called 'zz' (Z-Template).
	
Written By Zoda
Copyright (c) 2026 Kerem ATA (zoda)

Licensed under the MIT License (See: LICENSE)
this tool is part of dtools project (github.com/kerem3338/dtools)
**/
module dweb.tpl;

import std.stdio;
import std.file;
import std.path;
import std.conv;
import std.array;
import std.string;
import std.format;
import std.system;
import std.variant;
import std.datetime;
import std.typecons;
import std.algorithm;
import std.algorithm.searching;

version(EXECUTABLE) {
import argd;
}

struct ProgramInfo {
	string name;
	string description;
	string version_;
	string[] authors;
	string[string] links;

	this(string name, string description, string version_, string[] authors, string[string] links = null) {
		this.name = name;
		this.description = description;
		this.version_ = version_;
		this.authors = authors;
		this.links = links;
	}
}

__gshared ProgramInfo program = ProgramInfo(
	"template",
	"Custom text template tool",
	"0.0.1",
	["Kerem ATA (zoda)"]
);

// --actual program source--
// --enums
enum ErrorReporting : int {
	failOnError,
	failToOutput,
	ignoreErrors
}

enum ErrorType {
	syntaxError,
	internalError,
	invalidFunctionName,
	invalidVariableName,
	invalidArgumentCount,
	invalidPath,
	accessDenied
}

// --structs
struct Result {
	bool succeed;
	string message;

	static Result ok(string message = "") { return Result(true, message); }
	static Result fail(string message = "") { return Result(false, message); }

	bool opCast(T : bool)() const {
		return succeed;
	}
}

struct GenerationResult {
	Result result;
	string output;
}

struct Loc {
	int line = 1;
	int column = 1;

	string toString() const {
		return format("%d,%d", line, column);
	}
}

struct Variable {
	Variant value;
	bool readOnly;
}

struct TemplateError {
	ErrorType type;
	string message;
	Loc loc;

	string asHumaneString() {
		return format(
			"TemplateError (%s) at [%s:%s]\n\t%s",
			type, loc.line, loc.column, message
		);
	}
}

enum CmdOutputMode {
	console,
	capture,
	hidden
}

struct GenerationSettings {
	ErrorReporting errorReporting = ErrorReporting.ignoreErrors;
	bool allowStdio = true;
	bool trimTagLines = true;
	CmdOutputMode cmdOutputMode = CmdOutputMode.console;
	bool allowFileRead = true;
	bool allowFileWrite = true;
}

alias SettingDisabler = void delegate(ref GenerationSettings);
immutable SettingDisabler[string] disableMap;
shared static this() {
	disableMap = cast(immutable) [
		"fileRead":  (ref GenerationSettings s) { s.allowFileRead  = false; },
		"fileWrite": (ref GenerationSettings s) { s.allowFileWrite = false; },
		"fileIo":    (ref GenerationSettings s) { s.allowFileRead  = false; s.allowFileWrite = false; },
		"stdio":     (ref GenerationSettings s) { s.allowStdio     = false; },
	];
}

// --classes
abstract class TemplateFunction {
	string name;
	string description;
	
	int minArgs = -1;
	int maxArgs = -1;

	this(string name, string description = "") {
		this.name = name;
		this.description = description;
	}

	final Variant execute(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (minArgs != -1 && args.length < minArgs) {
			context.reportError(TemplateError(ErrorType.invalidArgumentCount, 
				format("Function '%s' requires at least %d arguments", name, minArgs), context.loc));
			return Variant("");
		}
		if (maxArgs != -1 && args.length > maxArgs) {
			context.reportError(TemplateError(ErrorType.invalidArgumentCount, 
				format("Function '%s' requires at most %d arguments", name, maxArgs), context.loc));
			return Variant("");
		}
		return call(args, data, context);
	}

	protected abstract Variant call(Variant[] args, ref Variant[string] data, TextTemplate context);
}

class BuiltinYearFunction : TemplateFunction {
	this() { super("__year__", "Returns current year"); maxArgs = 0; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		return Variant(Clock.currTime.year.to!string);
	}
}

class PlusOneFunction : TemplateFunction {
	this() { super("plusone", "Adds 1 to integer"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		return Variant(context.resolve(args[0], data).coerce!int + 1);
	}
}

class BuildPathFunction : TemplateFunction {
	this() { super("buildpath", "Builds a system path"); }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		string[] paths;
		foreach (arg; args) paths ~= context.resolve(arg, data).coerce!string;
		return Variant(buildPath(paths));
	}
}

class GenerateFunction : TemplateFunction {
	this() { super("generate", "Generates a sub-template"); minArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		string templatePath = context.resolve(args[0], data).coerce!string;
		if (!templatePath.exists || templatePath.isDir) {
			context.reportError(TemplateError(ErrorType.invalidPath, "Invalid template path: " ~ templatePath, context.loc));
			return Variant("");
		}
		Variant[string] childData;
		foreach (k, v; data) childData[k] = v;
		for (size_t i = 1; i < args.length; i++) {
			string argStr = context.resolve(args[i], data).coerce!string;
			auto eqIdx = argStr.indexOf('=');
			if (eqIdx != -1) childData[argStr[0 .. eqIdx].strip] = Variant(argStr[eqIdx + 1 .. $]);
		}
		try {
			TextTemplate subTemplate = new TextTemplate(readText(templatePath));
			subTemplate.functions = context.functions;
			subTemplate.variables = context.variables;
			return Variant(subTemplate.generate(childData).output);
		} catch (Exception e) {
			context.reportError(TemplateError(ErrorType.internalError, "generate failed: " ~ e.msg, context.loc));
			return Variant("");
		}
	}
}

class IncludeFunction : TemplateFunction {
	this() { super("include", "Includes file content"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		string includePath = context.resolve(args[0], data).coerce!string;
		if (!includePath.exists || includePath.isDir) {
			context.reportError(TemplateError(ErrorType.invalidPath, format("include path '%s' is invalid", includePath), context.loc));
			return Variant("");
		}
		try { return Variant(readText(includePath)); }
		catch (Exception e) {
			context.reportError(TemplateError(ErrorType.internalError, "include failed: " ~ e.msg, context.loc));
			return Variant("");
		}
	}
}

class DefinedFunction : TemplateFunction {
	this() { super("defined", "Checks if variable is defined"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		string varName = args[0].coerce!string;
		return Variant((varName in data) !is null || (varName in context.variables) !is null);
	}
}

class CwdFunction : TemplateFunction {
	this() { super("cwd", "Returns current working directory"); maxArgs = 0; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		return Variant(std.file.getcwd());
	}
}

class OsFunction : TemplateFunction {
	this() { super("os", "Returns current OS name"); maxArgs = 0; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		return Variant(to!string(std.system.os).toLower());
	}
}

class SetFunction : TemplateFunction {
	this() { super("set", "Sets a variable"); minArgs = 2; maxArgs = 2; }

	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		string varName = args[0].coerce!string;

		if (auto v = varName in context.variables) {
			if (v.readOnly) {
				context.reportError(
					TemplateError(
						ErrorType.accessDenied,
						format("variable '%s' is read-only", varName),
						context.loc
					)
				);
				return Variant("");
			}
		}

		data[varName] = context.resolve(args[1], data);
		return Variant("");
	}
}

class UpperFunction : TemplateFunction {
	this() { super("upper", "Converts string to uppercase"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		return Variant(context.resolve(args[0], data).coerce!string.toUpper());
	}
}

class LowerFunction : TemplateFunction {
	this() { super("lower", "Converts string to lowercase"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		return Variant(context.resolve(args[0], data).coerce!string.toLower());
	}
}

class FailFunction : TemplateFunction {
	this() { super("fail", "Reports an error and continues generation"); }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		string msg = args.length > 0 ? context.resolve(args[0], data).coerce!string : "Manual fail";
		context.reportError(TemplateError(ErrorType.internalError, msg, context.loc));
		return Variant("(error: " ~ msg ~ ")");
	}
}

class AbortFunction : TemplateFunction {
	this() { super("abort", "Immediately stops template generation, optionally printing a message to stderr"); }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (args.length > 0) {
			string msg = context.resolve(args[0], data).coerce!string;
			stderr.writeln(msg);
		}
		context.stopGeneration = true;
		return Variant("");
	}
}

class ReadFunction : TemplateFunction {
	this() { super("read", "Reads from stdin"); }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowStdio) {
			context.reportError(TemplateError(ErrorType.internalError, "read() is disabled by settings", context.loc));
			return Variant("");
		}
		if (args.length > 0) {
			write(context.resolve(args[0], data).coerce!string);
			stdout.flush();
		}
		return Variant(stdin.readln().strip());
	}
}

class CmdFunction : TemplateFunction {
	this() { super("cmd", "Executes shell command"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowStdio) {
			context.reportError(TemplateError(ErrorType.internalError, "cmd() is disabled by settings", context.loc));
			return Variant(-1);
		}
		import std.process : spawnShell, wait, executeShell;
		string command = context.resolve(args[0], data).coerce!string;
		try {
			if (context.settings.cmdOutputMode == CmdOutputMode.capture) {
				auto res = executeShell(command);
				return Variant(res.output.stripRight());
			} else if (context.settings.cmdOutputMode == CmdOutputMode.hidden) {
				auto res = executeShell(command);
				return Variant(res.status);
			} else {
				auto pid = spawnShell(command);
				return Variant(wait(pid));
			}
		} catch (Exception e) {
			context.reportError(TemplateError(ErrorType.internalError, "cmd failed: " ~ e.msg, context.loc));
			return Variant(-1);
		}
	}
}

class SetCmdModeFunction : TemplateFunction {
	this() { super("set_cmd_mode", "Sets cmd output mode"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		string mode = context.resolve(args[0], data).coerce!string;
		if (mode == "console") context.settings.cmdOutputMode = CmdOutputMode.console;
		else if (mode == "capture") context.settings.cmdOutputMode = CmdOutputMode.capture;
		else if (mode == "hidden") context.settings.cmdOutputMode = CmdOutputMode.hidden;
		else context.reportError(TemplateError(ErrorType.internalError, "Invalid cmd mode: " ~ mode, context.loc));
		return Variant("");
	}
}

class AsIntFunction : TemplateFunction {
	this() { super("as_int"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) { return Variant(context.resolve(args[0], data).coerce!int); }
}

class AsFloatFunction : TemplateFunction {
	this() { super("as_float"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) { return Variant(context.resolve(args[0], data).coerce!float); }
}

class AsStrFunction : TemplateFunction {
	this() { super("as_str"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) { return Variant(context.resolve(args[0], data).coerce!string); }
}

class NullFunction : TemplateFunction {
	this(string name) { super(name, "No-op function for blocks"); }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) { return Variant(""); }
}

// -- File I/O Functions

class FileExistsFunction : TemplateFunction {
	this() { super("file_exists", "Check whether a file or directory exists"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowFileRead) {
			context.reportError(TemplateError(ErrorType.internalError, "file_exists() is disabled by settings", context.loc));
			return Variant(false);
		}
		string path = context.resolve(args[0], data).coerce!string;
		return Variant(std.file.exists(path));
	}
}

class FileReadFunction : TemplateFunction {
	this() { super("file_read", "Read entire contents of a file as a string"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowFileRead) {
			context.reportError(TemplateError(ErrorType.internalError, "file_read() is disabled by settings", context.loc));
			return Variant("");
		}
		string path = context.resolve(args[0], data).coerce!string;
		try { return Variant(readText(path)); }
		catch (Exception e) {
			context.reportError(TemplateError(ErrorType.internalError, "file_read failed: " ~ e.msg, context.loc));
			return Variant("");
		}
	}
}

class FileWriteFunction : TemplateFunction {
	this() { super("file_write", "Write (overwrite) a string to a file"); minArgs = 2; maxArgs = 2; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowFileWrite) {
			context.reportError(TemplateError(ErrorType.internalError, "file_write() is disabled by settings", context.loc));
			return Variant(false);
		}
		string path = context.resolve(args[0], data).coerce!string;

		string absPath = path.absolutePath();
		string content = context.resolve(args[1], data).coerce!string;
		try {
			std.file.write(absPath, content);
			return Variant(true);
		} catch (Exception e) {
			context.reportError(TemplateError(ErrorType.internalError, "file_write failed: " ~ e.msg, context.loc));
			return Variant(false);
		}
	}
}

class FileAppendFunction : TemplateFunction {
	this() { super("file_append", "Append a string to a file (creates if not exists)"); minArgs = 2; maxArgs = 2; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowFileWrite) {
			context.reportError(TemplateError(ErrorType.internalError, "file_append() is disabled by settings", context.loc));
			return Variant(false);
		}
		string path = context.resolve(args[0], data).coerce!string;
		string content = context.resolve(args[1], data).coerce!string;
		try {
			append(path, content);
			return Variant(true);
		} catch (Exception e) {
			context.reportError(TemplateError(ErrorType.internalError, "file_append failed: " ~ e.msg, context.loc));
			return Variant(false);
		}
	}
}

class FileDeleteFunction : TemplateFunction {
	this() { super("file_delete", "Delete a file"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowFileWrite) {
			context.reportError(TemplateError(ErrorType.internalError, "file_delete() is disabled by settings", context.loc));
			return Variant(false);
		}
		string path = context.resolve(args[0], data).coerce!string;
		try {
			if (std.file.exists(path)) std.file.remove(path);
			return Variant(true);
		} catch (Exception e) {
			context.reportError(TemplateError(ErrorType.internalError, "file_delete failed: " ~ e.msg, context.loc));
			return Variant(false);
		}
	}
}

class FileMkdirFunction : TemplateFunction {
	this() { super("file_mkdir", "Create a directory (including parents)"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowFileWrite) {
			context.reportError(TemplateError(ErrorType.internalError, "file_mkdir() is disabled by settings", context.loc));
			return Variant(false);
		}
		string path = context.resolve(args[0], data).coerce!string;
		try {
			if (!std.file.exists(path)) std.file.mkdirRecurse(path);
			return Variant(true);
		} catch (Exception e) {
			context.reportError(TemplateError(ErrorType.internalError, "file_mkdir failed: " ~ e.msg, context.loc));
			return Variant(false);
		}
	}
}

class FileListFunction : TemplateFunction {
	this() { super("file_list", "List files/dirs in a directory, returned as newline-separated string"); minArgs = 1; maxArgs = 2; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
        if (!context.settings.allowFileRead) {
            context.reportError(TemplateError(ErrorType.internalError, "file_list() is disabled by settings", context.loc));
            return Variant("");
        }
        string path;
        string filter = "all";
        // If first argument is a known filter and there is a second argument, treat first as filter.
        if (args.length >= 2) {
            string first = context.resolve(args[0], data).coerce!string;
            string second = context.resolve(args[1], data).coerce!string;
            if (first == "files" || first == "dirs" || first == "all") {
                filter = first;
                path = second;
            } else {
                path = first;
                filter = second;
            }
        } else if (args.length == 1) {
            path = context.resolve(args[0], data).coerce!string;
        } else {
            context.reportError(TemplateError(ErrorType.invalidArgumentCount, "file_list requires at least a path argument", context.loc));
            return Variant("");
        }
        if (!path.exists) {
            context.reportError(TemplateError(ErrorType.invalidPath, "Invalid path for file_list: " ~ path, context.loc));
            return Variant("");
        }
        try {
            string[] entries;
            foreach (entry; std.file.dirEntries(path, std.file.SpanMode.shallow)) {
                if (filter == "files" && entry.isDir) continue;
                if (filter == "dirs" && !entry.isDir) continue;
                entries ~= entry.name;
            }
            return Variant(entries.join("\n"));
        } catch (Exception e) {
            context.reportError(TemplateError(ErrorType.internalError, "file_list failed: " ~ e.msg, context.loc));
            return Variant("");
        }
    }
}

class FileIsFileFunction : TemplateFunction {
	this() { super("file_isfile", "Returns true if path is an existing file"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowFileRead) {
			context.reportError(TemplateError(ErrorType.internalError, "file_isfile() is disabled by settings", context.loc));
			return Variant(false);
		}
		string path = context.resolve(args[0], data).coerce!string;
		return Variant(std.file.exists(path) && !std.file.isDir(path));
	}
}

class FileIsDirFunction : TemplateFunction {
	this() { super("file_isdir", "Returns true if path is an existing directory"); minArgs = 1; maxArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowFileRead) {
			context.reportError(TemplateError(ErrorType.internalError, "file_isdir() is disabled by settings", context.loc));
			return Variant(false);
		}
		string path = context.resolve(args[0], data).coerce!string;
		return Variant(std.file.exists(path) && std.file.isDir(path));
	}
}

class WriteFunction : TemplateFunction {
	this() { super("write", "Writes to stdout (doesn't appear in template output)"); minArgs = 1; }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowStdio) {
			context.reportError(TemplateError(ErrorType.internalError, "write() is disabled by settings", context.loc));
			return Variant(false);
		}
		string[] parts;
		foreach (arg; args)
			parts ~= context.resolve(arg, data).coerce!string;
		write(parts.join(" "));
		return Variant("");
	}
}

class WritelnFunction : TemplateFunction {
	this() { super("writeln", "Writes a line to stdout (doesn't appear in template output)"); }
	protected override Variant call(Variant[] args, ref Variant[string] data, TextTemplate context) {
		if (!context.settings.allowStdio) {
			context.reportError(TemplateError(ErrorType.internalError, "writeln() is disabled by settings", context.loc));
			return Variant(false);
		}
		string[] parts;
		foreach (arg; args)
			parts ~= context.resolve(arg, data).coerce!string;
		writeln(parts.join(" "));
		return Variant("");
	}
}

class TextTemplate {
	string src;

	size_t cursor;
	bool stopGeneration = false;
	Loc loc = Loc();
	TemplateError[] errors;

	GenerationSettings settings;
	ErrorReporting errorReporting = ErrorReporting.failOnError;

	TemplateFunction[string] functions;
	Variable[string] variables;

	void registerFunction(TemplateFunction fn) {
		functions[fn.name] = fn;
	}

	string[string] blockPairs;

	this(string src) {
		this.src = src;
		blockPairs["while"] = "endwhile";
		blockPairs["if"] = "endif";
		blockPairs["script"] = "endscript";
		setDefaults();
	}

	void clean() {
		cursor = 
		stopGeneration = false;
		loc = Loc();
		errors = [];

		foreach (string key, Variable var; variables.dup) {
			if (!var.readOnly)
				variables.remove(key);
		}
	}

	Variant resolve(Variant v, ref Variant[string] data) {
		if (v.type != typeid(string)) return v;
		return evaluate(v.coerce!string, data);
	}

	string[] splitArgs(string s) {
		string[] result;
		int depth = 0;
		size_t start = 0;
		bool inQuotes = false;
		for (size_t i = 0; i < s.length; i++) {
			if (s[i] == '"') inQuotes = !inQuotes;
			if (inQuotes) continue;
			if (s[i] == '(') depth++;
			if (s[i] == ')') depth--;
			if (s[i] == ',' && depth == 0) {
				result ~= s[start .. i].strip;
				start = i + 1;
			}
		}
		if (start < s.length || s.length == 0)
			result ~= s[start .. $].strip;
		return result;
	}

	static string variantToString(Variant v) {
		if (v.type == typeid(bool))   return v.get!bool ? "true" : "false";
		if (v.type == typeid(int))    return v.get!int.to!string;
		if (v.type == typeid(float))  return v.get!float.to!string;
		if (v.type == typeid(double)) return v.get!double.to!string;
		try { return v.coerce!string; } catch (Exception) { return v.toString(); }
	}

	Variant compare(Variant a, string op, Variant b) {
		if (a.type == typeid(bool) && b.type == typeid(bool)) {
			bool ba = a.get!bool, bb = b.get!bool;
			switch (op) {
				case "==": return Variant(ba == bb);
				case "!=": return Variant(ba != bb);
				default:   break;
			}
		}

		try {
			double na = a.coerce!double;
			double nb = b.coerce!double;
			switch (op) {
				case "==": return Variant(na == nb);
				case "!=": return Variant(na != nb);
				case "<":  return Variant(na < nb);
				case ">":  return Variant(na > nb);
				case "<=": return Variant(na <= nb);
				case ">=": return Variant(na >= nb);
				default: break;
			}
		} catch (Exception) {}

		string sa = variantToString(a);
		string sb = variantToString(b);
		switch (op) {
			case "==": return Variant(sa == sb);
			case "!=": return Variant(sa != sb);
			case "<":  return Variant(sa < sb);
			case ">":  return Variant(sa > sb);
			case "<=": return Variant(sa <= sb);
			case ">=": return Variant(sa >= sb);
			default:   return Variant(false);
		}
	}

	Variant evaluate(string content, ref Variant[string] data) {
		content = content.strip;
		if (content.length == 0) return Variant("");

		bool isSafe(size_t idx, string s) {
			bool inQuotes = false;
			int depth = 0;
			for (size_t i = 0; i < idx; i++) {
				if (s[i] == '"') inQuotes = !inQuotes;
				if (inQuotes) continue;
				if (s[i] == '(') depth++;
				if (s[i] == ')') depth--;
			}
			return !inQuotes && depth == 0;
		}

		auto orIdx = content.indexOf("||");
		if (orIdx != -1 && isSafe(orIdx, content)) {
			auto left = evaluate(content[0 .. orIdx], data);
			auto right = evaluate(content[orIdx + 2 .. $], data);
			return Variant(left.coerce!bool || right.coerce!bool);
		}

		auto andIdx = content.indexOf("&&");
		if (andIdx != -1 && isSafe(andIdx, content)) {
			auto left = evaluate(content[0 .. andIdx], data);
			auto right = evaluate(content[andIdx + 2 .. $], data);
			return Variant(left.coerce!bool && right.coerce!bool);
		}

		auto concatTildeIdx = content.lastIndexOf("~");
		if (concatTildeIdx != -1 && isSafe(concatTildeIdx, content)) {
			auto left = evaluate(content[0 .. concatTildeIdx], data);
			auto right = evaluate(content[concatTildeIdx + 1 .. $], data);
			return Variant(left.coerce!string ~ right.coerce!string);
		}

		auto addIdx = content.lastIndexOf("+");
		if (addIdx != -1 && isSafe(addIdx, content)) {
			auto left = evaluate(content[0 .. addIdx], data);
			auto right = evaluate(content[addIdx + 1 .. $], data);
			
			if ((left.type == typeid(int) || left.type == typeid(double)) &&
				(right.type == typeid(int) || right.type == typeid(double))) {
				try {
					if (left.type == typeid(int) && right.type == typeid(int)) {
						return Variant(left.coerce!int + right.coerce!int);
					}
					return Variant(left.coerce!double + right.coerce!double);
				} catch (Exception) {}
			}
			
			return Variant(left.coerce!string ~ right.coerce!string);
		}

		static immutable string[] cmpOps = ["==", "!=", "<=", ">=", "<", ">"];
		foreach (op; cmpOps) {
			auto idx = content.indexOf(op);
			if (idx != -1 && isSafe(idx, content)) {
				auto left = evaluate(content[0 .. idx].strip, data);
				auto right = evaluate(content[idx + op.length .. $].strip, data);
				return compare(left, op, right);
			}
		}

		if (content.length >= 2 && ((content[0] == '"' && content[$ - 1] == '"') || (content[0] == '\'' && content[$ - 1] == '\''))) {
			string s = content[1 .. $ - 1];
			string result;
			size_t i = 0;
			while (i < s.length) {
				if (s[i] == '$' && i + 1 < s.length && s[i+1] == '{') {
					auto end = s.indexOf('}', i);
					if (end != -1) {
						string varName = s[i + 2 .. end];
						if (varName in data) result ~= data[varName].coerce!string;
						else if (varName in variables) result ~= variables[varName].value.coerce!string;
						else result ~= "${" ~ varName ~ "}";
						i = end + 1;
						continue;
					}
				}
				result ~= s[i++];
			}
			return Variant(result);
		}

		auto openParen = content.indexOf('(');
		if (openParen != -1 && content.endsWith(")")) {
			string name = content[0 .. openParen].strip;
			string inside = content[openParen + 1 .. $ - 1].strip;

			Variant[] args;
			string[] rawArgs = splitArgs(inside);
			foreach (raw; rawArgs) {
				if (raw.length > 0)
					args ~= evaluate(raw, data);
			}

			if (name in functions) {
				return functions[name].execute(args, data, this);
			} else {
				reportError(TemplateError(ErrorType.invalidFunctionName, "Unknown function: " ~ name, loc));
				return Variant("(unknown func: " ~ name ~ ")");
			}
		} else if (content in functions) {
			return functions[content].execute([], data, this);
		}

		if (content.all!(c => c >= '0' && c <= '9')) {
			return Variant(content.to!int);
		}

		if (content.length > 0) {
			bool isFloat = true;
			bool hasDot = false;
			foreach (i, c; content) {
				if (c == '.' && !hasDot) { hasDot = true; continue; }
				if (c < '0' || c > '9') { isFloat = false; break; }
			}
			if (isFloat && hasDot) return Variant(content.to!float);
		}

		if (content == "true")  return Variant(true);
		if (content == "false") return Variant(false);
		if (content == "null")  return Variant("");

		if (content in data) return data[content];
		if (content in variables) return variables[content].value;

		return Variant(content);
	}

	void setDefaults() {
		variables["__version__"] = Variable(Variant(program.version_), true);
		
		registerFunction(new BuiltinYearFunction());
		registerFunction(new PlusOneFunction());
		registerFunction(new BuildPathFunction());
		registerFunction(new GenerateFunction());
		registerFunction(new IncludeFunction());
		registerFunction(new DefinedFunction());
		registerFunction(new CwdFunction());
		registerFunction(new OsFunction());
		registerFunction(new SetFunction());
		registerFunction(new UpperFunction());
		registerFunction(new LowerFunction());
		registerFunction(new FailFunction());
		registerFunction(new AbortFunction());
		registerFunction(new ReadFunction());
		registerFunction(new CmdFunction());
		registerFunction(new SetCmdModeFunction());
		registerFunction(new WriteFunction());
		registerFunction(new WritelnFunction());
		
		auto asIntFn = new AsIntFunction();
		registerFunction(asIntFn);
		auto asFloatFn = new AsFloatFunction();
		registerFunction(asFloatFn);
		auto asStrFn = new AsStrFunction();
		registerFunction(asStrFn);
		
		functions["asint"] = asIntFn;
		functions["asfloat"] = asFloatFn;
		functions["asstr"] = asStrFn;
		
		registerFunction(new NullFunction("endif"));
		registerFunction(new NullFunction("endwhile"));
		registerFunction(new NullFunction("endscript"));

		registerFunction(new FileExistsFunction());
		registerFunction(new FileReadFunction());
		registerFunction(new FileWriteFunction());
		registerFunction(new FileAppendFunction());
		registerFunction(new FileDeleteFunction());
		registerFunction(new FileMkdirFunction());
		registerFunction(new FileListFunction());
		registerFunction(new FileIsFileFunction());
		registerFunction(new FileIsDirFunction());
	}

	bool eof() { return cursor >= src.length; }
	char peek() { return eof() ? 0 : src[cursor]; }
	bool hasFailed() { return errors.length > 0; }

	string decodeChar(char c)
	{
		if (c != '\\')
			return to!string(c);

		if (eof())
			return "\\";

		auto n = peek();

		switch (n)
		{
			case 'n': advance(); return "\n";
			case 't': advance(); return "\t";
			case 'r': advance(); return "\r";
			case '\\': advance(); return "\\";
			default: return "\\";
		}
	}

	char advance() {
		if (eof()) return 0;

		auto c = src[cursor++];

		if (c == '\n') {
			loc.line++;
			loc.column = 1;
		} else {
			loc.column++;
		}

		return c;
	}

	bool match(string s) {
		if (cursor + s.length > src.length) return false;
		if (src[cursor .. cursor + s.length] == s) {
			cursor += s.length;
			return true;
		}
		return false;
	}

	string readUntil(string end) {
		size_t start = cursor;

		while (!eof()) {
			if (match(end))
				break;
			advance();
		}

		size_t endPos = cursor >= end.length ? cursor - end.length : start;
		return src[start .. endPos];
	}

	void reportError(TemplateError error) {
		final switch (errorReporting) {
			case ErrorReporting.failOnError:
				errors ~= error;
				stopGeneration = true;
				break;

			case ErrorReporting.failToOutput:
				errors ~= error;
				break;

			case ErrorReporting.ignoreErrors:
				return;
		}
	}

	GenerationResult generate() {
		Variant[string] data;
		return generate(data);
	}

	GenerationResult generate(ref Variant[string] data) {
		string output;

		void tryTrimLine() {
			if (!settings.trimTagLines) return;
			bool onlyWhiteBefore = false;
			if (output.length == 0) {
				onlyWhiteBefore = true;
			} else {
				import std.string : lastIndexOf;
				import std.algorithm : all;
				auto lastNL = output.lastIndexOf('\n');
				string lastLinePart = (lastNL == -1) ? output : output[lastNL + 1 .. $];
				if (lastLinePart.all!(c => c == ' ' || c == '\t' || c == '\r')) {
					onlyWhiteBefore = true;
				}
			}

			if (onlyWhiteBefore) {
				size_t tempCursor = cursor;
				bool onlyWhiteAfter = true;
				while (tempCursor < src.length) {
					if (src[tempCursor] == '\n') break;
					if (src[tempCursor] != ' ' && src[tempCursor] != '\t' && src[tempCursor] != '\r') {
						onlyWhiteAfter = false;
						break;
					}
					tempCursor++;
				}
				
				if (onlyWhiteAfter && tempCursor < src.length && src[tempCursor] == '\n') {
					import std.string : lastIndexOf;
					auto lastNL = output.lastIndexOf('\n');
					output = (lastNL == -1) ? "" : output[0 .. lastNL + 1];

					cursor = tempCursor + 1;
					loc.line++;
					loc.column = 1;
				}
			}
		}

		while (!eof()) {
			bool shouldAddvance = true;

			if (stopGeneration)
				break;

			bool isFunc = false;
			bool isVar = false;
			bool stripLeft = false;
			bool stripRight = false;
			string content;
			bool isLong = false;
			string endTag;

			if (match("{-")) {
				readUntil("-}");
				tryTrimLine();
				continue;
			}

			if (match("{{#")) {
				isFunc = true;
				isLong = true;
				if (peek() == '-') { advance(); stripLeft = true; }
				endTag = "#}}";
				content = readUntil(endTag);
				if (content.endsWith("-")) {
					content = content[0 .. $ - 1];
					stripRight = true;
				}
			} else if (match("{#")) {
				isFunc = true;
				isLong = false;
				if (peek() == '-') { advance(); stripLeft = true; }
				endTag = "#}";
				content = readUntil(endTag);
				if (content.endsWith("-")) {
					content = content[0 .. $ - 1];
					stripRight = true;
				}
			} else if (match("{%")) {
				isFunc = true;
				if (peek() == '-') { advance(); stripLeft = true; }
				content = readUntil("%}");
				if (content.endsWith("-")) {
					content = content[0 .. $ - 1];
					stripRight = true;
				}
			} else if (match("{{")) {
				isVar = true;
				if (peek() == '-') { advance(); stripLeft = true; }
				content = readUntil("}}");
				if (content.endsWith("-")) {
					content = content[0 .. $ - 1];
					stripRight = true;
				}
			}

			if (isFunc || isVar) {
				if (stripLeft) {
					output = output.stripRight;
				}

				if (isFunc) {
					auto openParen = content.indexOf('(');
					string name = (openParen == -1) ? content.strip : content[0 .. openParen].strip;

					if (name in blockPairs) {
						string endTagName = blockPairs[name];
						string body_;
						int depth = 1;

						if (stripRight) {
							import std.ascii : isWhite;
							while (!eof() && src[cursor].isWhite) {
								advance();
							}
							stripRight = false; // Already done
						}
						
						size_t bodyStart = cursor;
						string trueBody, falseBody;
						bool hasElse = false;
						
						while (!eof()) {
							size_t currentPos = cursor;
							bool innerIsFunc = false;
							string innerEndTag;
							if (match("{{#")) { innerIsFunc = true; innerEndTag = "#}}"; }
							else if (match("{#")) { innerIsFunc = true; innerEndTag = "#}"; }
							else if (match("{%")) { innerIsFunc = true; innerEndTag = "%}"; }

							if (innerIsFunc) {
								auto innerContent = readUntil(innerEndTag);
								if (innerContent.startsWith("-")) innerContent = innerContent[1 .. $];
								if (innerContent.endsWith("-")) innerContent = innerContent[0 .. $ - 1];
								
								auto innerOpenParen = innerContent.indexOf('(');
								string innerName = (innerOpenParen == -1) ? innerContent.strip : innerContent[0 .. innerOpenParen].strip;
								
								if (innerName == name) depth++;
								else if (innerName == endTagName) depth--;
								else if (innerName == "else" && depth == 1 && name == "if") {
									trueBody = src[bodyStart .. currentPos];
									hasElse = true;
									bodyStart = cursor;
									continue;
								}
								
								if (depth == 0) {
									if (hasElse) falseBody = src[bodyStart .. currentPos];
									else trueBody = src[bodyStart .. currentPos];
									break;
								}
							} else {
								advance();
							}
						}
						
						string cond = "";
						if (openParen != -1) {
							auto closeParen = content.lastIndexOf(')');
							if (closeParen != -1 && closeParen > openParen)
								cond = content[openParen + 1 .. closeParen].strip;
							else
								cond = content[openParen + 1 .. $].strip;
						}

						if (depth > 0) {
							reportError(TemplateError(ErrorType.syntaxError, "Missing end tag for block: " ~ name, loc));
							continue;
						}

						body_ = trueBody;

						if (name == "if") {
							if (evaluate(cond, data).coerce!bool) {
								auto subTemplate = new TextTemplate(trueBody);
								subTemplate.functions = this.functions;
								subTemplate.variables = this.variables;
								subTemplate.settings = this.settings;
								auto res = subTemplate.generate(data);
								output ~= res.output;
								if (subTemplate.stopGeneration) { this.stopGeneration = true; break; }
							} else if (hasElse) {
								auto subTemplate = new TextTemplate(falseBody);
								subTemplate.functions = this.functions;
								subTemplate.variables = this.variables;
								subTemplate.settings = this.settings;
								auto res = subTemplate.generate(data);
								output ~= res.output;
								if (subTemplate.stopGeneration) { this.stopGeneration = true; break; }
							}
						} else if (name == "while") {
							while (evaluate(cond, data).coerce!bool) {
								auto subTemplate = new TextTemplate(body_);
								subTemplate.functions = this.functions;
								subTemplate.variables = this.variables;
								subTemplate.settings = this.settings;
								auto res = subTemplate.generate(data);
								output ~= res.output;
								if (subTemplate.stopGeneration) { this.stopGeneration = true; break; }
							}
						} else if (name == "script") {
							auto subTemplate = new TextTemplate(body_);
							subTemplate.functions = this.functions;
							subTemplate.variables = this.variables;
							subTemplate.settings = this.settings;
							subTemplate.generate(data); // Discard output
							if (subTemplate.stopGeneration) { this.stopGeneration = true; break; }
						}
					} else {
						output ~= evaluate(content, data).coerce!string;
					}
				} else {
					bool canBeNull = true;
					string key = content.strip;

					if (key.length >= 1 && key[0] == '@') {
						canBeNull = false;
						key = key[1 .. $];
					}

					auto val = evaluate(key, data);
					
					if (val.type == typeid(string) && val.coerce!string == key && !(key in data) && !(key in variables)) {
						if (canBeNull) {
							shouldAddvance = false;
						} else {
							reportError(TemplateError(ErrorType.invalidVariableName, "Missing variable: " ~ key, loc));
							output ~= "{{" ~ key ~ "}}";
						}
					} else {
						output ~= val.coerce!string;
					}
				}

				if (stripRight) {
					import std.ascii : isWhite;
					while (!eof() && src[cursor].isWhite) {
						advance();
					}
				} else if (settings.trimTagLines) {
					tryTrimLine();
				}
				continue;
			}

			if (shouldAddvance)
				output ~= advance();
		}

		Result res = Result.ok();

		if (hasFailed())
			res = Result.fail(format("Template generated %d errors.", errors.length));

		return GenerationResult(res, output);
	}
}

// START OF "version (EXECUTABLE) {"
// START OF COMMANDS
version (EXECUTABLE) {
class GenerateCommand : Command {
	this() {
		super("generate");
		description = "Generate output from a template file";
		usage = "<template file or string> <variable=value> ... [options]";
		argCollType = ArgCollectionType.minimum;
		argCount = 1;

		addOption("--asstring", "-str", "Instead of loadimh from a file, load given string as template source");
		addOption("--save", "-s", "Save the generated output to a file", "filepath");
		addOption("--error", "-e", "Set the error reporting level", "value");
		addOption("--data", "-d", "Load datas for template from a file", "filepath");
		addOption("--disable", "", "Comma-separated list of features to disable. Tokens: fileRead, fileWrite, fileIo, stdio", "features");
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string templateFile = args[0];
		string templateSrc;
		string[] dataArgs = args[0 .. $];
		Variant[string] data;

		if (hasOption("--data", "-d")) {
			string dataArgsFp = getOption("--data", "-d");
			
			if (!templateFile.exists) return CommandResult.error(format("data file '%s' doesnt exists.", dataArgsFp));
			dataArgs = readText(dataArgsFp).splitLines();
		}

		if (!hasOption("--asstring", "-str")) {
			if (!templateFile.exists) return CommandResult.error(format("template file '%s' doesnt exists.", templateFile));
		}

		foreach (arg; dataArgs) {
			if (std.string.strip(arg).length <= 3) continue;
			size_t eq = arg.indexOf('=');

			if (eq == -1) {
				data[arg] = Variant("");
			} else {
				string key = arg[0 .. eq].strip;
				string value = arg[eq + 1 .. $];

				data[key] = Variant(unescape(value));
			}
		}

		if (!hasOption("--asstring", "-str")) {
			try {
				templateSrc = readText(templateFile);
			} catch (Exception e) {
				return CommandResult.error(format("Something bad happened while reading template file: %s", e.toString()));
			}
		} else {
			templateSrc = templateFile;
		}

		TextTemplate template_ = new TextTemplate(templateSrc);

		if (hasOption("--error", "-e")) {
			string errorReportLevel = getOption("--error", "-e");
			template_.errorReporting = to!ErrorReporting(errorReportLevel);
		}

		if (hasOption("--disable", "")) {
			foreach (token; getOption("--disable", "").split(',')) {
				string t = token.strip;
				if (auto fn = t in disableMap)
					(*fn)(template_.settings);
				else
					writefln("Warning: unknown --disable token '%s' (valid: %s)", t, (cast(SettingDisabler[string]) disableMap).keys.join(", "));
			}
		}

		GenerationResult genResult = template_.generate(data);

		if (!genResult.result && template_.errorReporting == ErrorReporting.failOnError) {
			if (!quiet) writefln("** Generation Failed **\nTotal of %d errors generated by the template", template_.errors.length);
			foreach(TemplateError error; template_.errors) {
				writeln(error.asHumaneString());
			}
		} else {
			if (verbose) writefln("** Generation succeed.");
			write(genResult.output);
			if (hasOption("--save", "-s")) std.file.write(getOption("--save", "-s"), genResult.output);
		}

		return CommandResult.ok();
	}
}
class AboutCommand : Command {
	this() {
		super("about");
		description = format("Provides detailed information about the %s", program.name);
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		writefln("%s (version: %s)

%s

Written by Kerem ATA (zoda), licensed under the MIT License (see LICENSE)
Github: https://github.com/kerem3338/
Dtools (Repo): https://github.com/kerem3338/dtools

This tool is part of dtools project.", program.name, program.version_, program.description);
		return CommandResult.ok();
	}
}

class RootCommand : Command {
	this() {
		super(program.name);
		description = program.description;
		usage = "<command> <subcommand> [options]";

		addOption("--verbose", "-V", "Enable verbose output");
		addOption("--quiet", "-q", "Suppress output");
		addOption("--gen-docs", "-gd", "Generate markdown documentation");
		addOption("--gen-html", "-gh", "Generate HTML documentation");
		addOption("--version", "-v", "Show version");
		
		argCollType = ArgCollectionType.any;

		registerSubCommand(new GenerateCommand());
		registerSubCommand(new AboutCommand());
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {

		bool docGenerated = false;
		if (hasOption("--gen-docs", "-gd")) {
			std.file.write(program.name ~"_DOCUMENTATION.md", buildMarkdown());
			writeln("Docs generated");
			docGenerated = true;
		}

		if (hasOption("--gen-html", "-gh")) {
			std.file.write(program.name~"_DOCUMENTATION.html", buildHTML());
			writeln("HTML docs generated");
			docGenerated = true;
		}

		if (docGenerated) return CommandResult.ok();

		if (hasOption("--version", "-v")) {
			if (!hasOption("--quiet", "-q"))
				writefln("%s version %s", program.name, program.version_);
			else
				writeln(program.version_);

			return CommandResult.ok();
		}

		if (args.length == 0) {
			return CommandResult.ok(buildHelp());
		}

		return CommandResult.error("Unknown input: " ~ args.join(" ") ~ "\n\n" ~ buildHelp(), 1);
	}
}

}
// END FOR "version (EXECUTABLE) {"
// END OF COMMANDS

// --functions
string unescape(string s) {
	string result;
	for (size_t i = 0; i < s.length; i++) {
		if (s[i] == '\\' && i + 1 < s.length) {
			i++;
			switch (s[i]) {
				case 'n': result ~= "\n"; break;
				case 't': result ~= "\t"; break;
				case 'r': result ~= "\r"; break;
				case '\\': result ~= "\\"; break;
				case '\"': result ~= "\""; break;
				case '\'': result ~= "\'"; break;
				default: result ~= "\\" ~ s[i]; break;
			}
		} else {
			result ~= s[i];
		}
	}
	return result;
}

version (EXECUTABLE) {

int main(string[] args) {
	auto root = new RootCommand();
	
	auto result = root.handle(args.length > 1 ? args[1 .. $] : []);
	if (result.message.length > 0)
	{
		writeln(result.message);
	}
	if (!result.success)
	{
		return result.exitCode;
	}
	return 0;

}

}