module dweb.common;

import std.conv;

struct Version {
	uint major;
	uint minor;
	uint patch;

	string toString() const {
		return major.to!string ~ minor.to!string ~ patch.to!string; 
	}
}

const Version DWEB_VERSION = Version(0,1,0);