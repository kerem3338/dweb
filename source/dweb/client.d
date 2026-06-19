module dweb.client;

import dweb.request;
import std.socket;
import std.conv;

class Client {
    Socket socket;

    string ip;
    ushort port;

    Request request;

    this(Socket socket) {
        this.socket = socket;

        auto addr = socket.remoteAddress();

        ip = addr.toAddrString();
        port = addr.toPortString().to!ushort;
    }
}