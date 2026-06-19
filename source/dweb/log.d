module dweb.log;

import std.stdio;
import std.file;
import std.datetime;
import std.format;
import core.sync.mutex;
import std.array;

struct LogRecord {
	string type;
	string message;
	SysTime timestamp;
    string loggerName;

	static LogRecord create(string type, string message, string loggerName = "") {
		return LogRecord(type, message, Clock.currTime(), loggerName);
	}

	private this(string type, string message, SysTime timestamp, string loggerName) {
		this.type = type;
		this.message = message;
		this.timestamp = timestamp;
        this.loggerName = loggerName;
	}

	string toString() const {
        string prefix = loggerName.length > 0 ? "[" ~ loggerName ~ "]" : "";
		return format("%s[%s][%s] %s", prefix, type, timestamp.toISOExtString(), message);
	}
}

interface ILogHandler {
	void handle(LogRecord record);
}

class ConsoleHandler : ILogHandler {
	void handle(LogRecord record) {
		writeln(record.toString());
	}
}

class FileHandler : ILogHandler {
	private string filePath;
	private Mutex m;

	this(string filePath) { this.filePath = filePath; this.m = new Mutex(); }

	void handle(LogRecord record) {
		m.lock();
		try { std.file.append(filePath, record.toString() ~ "\n"); }
		finally { m.unlock(); }
	}
}  

class MemoryHandler : ILogHandler {
	private LogRecord[] buffer;
	private Mutex m;

	this() { this.m = new Mutex(); }

	void handle(LogRecord record) {
		m.lock();
		buffer ~= record;
		m.unlock();
	}

	LogRecord[] getLogs() {
		m.lock();
		auto copy = buffer.dup;
		m.unlock();
		return copy;
	}
}

class Logger {
	private ILogHandler[] handlers;
	private Mutex m;
    string name;

	this(string name = "") { this.m = new Mutex(); this.name = name; }

	private bool _initialized = false;

	void addHandler(ILogHandler handler) { handlers ~= handler; }

	void init() {
		m.lock();
        scope(exit) m.unlock();
        
		if (!_initialized) {
            if (handlers.length == 0) {
			    addHandler(new ConsoleHandler());
            }
			_initialized = true;
		}
	}

    Logger createChild(string name) {
        init();
        auto child = new Logger(name);
        child.handlers = this.handlers;
        child._initialized = true;
        return child;
    }

	void log(string type, string message, string explicitLoggerName = null) {
		init();
        string finalName = explicitLoggerName !is null ? explicitLoggerName : name;
		auto record = LogRecord.create(type, message, finalName);
		m.lock();
		foreach(h; handlers) {
            if (h !is null) {
			    h.handle(record);
            }
		}
		m.unlock();
	}

	void info(string msg, string loggerName = null)  { log("INFO", msg, loggerName); }
	void debug_(string msg, string loggerName = null) { log("DEBUG", msg, loggerName); }
	void warn(string msg, string loggerName = null)  { log("WARN", msg, loggerName); }
	void error(string msg, string loggerName = null) { log("ERROR", msg, loggerName); }
}
