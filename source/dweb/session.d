module dweb.session;

import std.uuid;
import std.datetime.systime;
import core.time;

class Session {
    string id;
    string[string] data;
    long expiresAt;

    this(string id, long ttlSeconds = 3600) {
        this.id = id;
        this.expiresAt = Clock.currTime().toUnixTime() + ttlSeconds;
    }

    bool isExpired() const {
        return Clock.currTime().toUnixTime() > expiresAt;
    }
}

class SessionStore {
    private Session[string] sessions;
    private long ttlSeconds;

    this(long ttlSeconds = 3600) {
        this.ttlSeconds = ttlSeconds;
    }

    string generateSecureSessionId() {
        return randomUUID().toString();
    }

    Session getOrCreate(string sid) {
        if (sid.length > 0) {
            auto p = sid in sessions;
            if (p !is null && !(*p).isExpired()) {
                // refresh TTL on access
                (*p).expiresAt = Clock.currTime().toUnixTime() + ttlSeconds;
                return *p;
            }
            
            // if expired, clean it up immediately
            if (p !is null) {
                sessions.remove(sid);
            }
        }

        // Create new
        string newId = generateSecureSessionId();
        auto session = new Session(newId, ttlSeconds);
        sessions[newId] = session;
        return session;
    }

    void cleanup() {
        auto now = Clock.currTime().toUnixTime();
        string[] expiredKeys;
        foreach (k, v; sessions) {
            if (v.expiresAt < now) {
                expiredKeys ~= k;
            }
        }
        foreach (k; expiredKeys) {
            sessions.remove(k);
        }
    }
}
