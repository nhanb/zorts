const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const mem = std.mem;
const log = std.log.scoped(.WebServer);
const fmt = std.fmt;
const State = @import("./State.zig");

const Self = @This();

pub const PORT = 1337;
pub const WEB_DIR = "web";

gpa: std.mem.Allocator,
io: Io,
state: *State,
state_mutex: *Io.Mutex,
shutting_down: bool,
tcp_server: net.Server,
server_thread: std.Thread,

pub fn init(
    gpa: std.mem.Allocator,
    io: Io,
    state: *State,
    state_mutex: *Io.Mutex,
) !*Self {
    var self = try gpa.create(Self);
    self.gpa = gpa;
    self.io = io;
    self.state = state;
    self.state_mutex = state_mutex;
    self.shutting_down = false;

    const address: net.IpAddress = .{
        .ip4 = .{
            .bytes = .{ 127, 0, 0, 1 },
            .port = PORT,
        },
    };
    self.tcp_server = try address.listen(io, .{ .reuse_address = true });
    self.server_thread = try .spawn(.{}, startServer, .{self});

    return self;
}

pub fn deinit(self: *Self) void {
    self.shutting_down = true;
    var stream = self.tcp_server.socket.address.connect(self.io, .{ .mode = .stream }) catch
        @panic("shutdown failure");
    stream.close(self.io);
    self.server_thread.join();
    self.tcp_server.deinit(self.io);
    self.gpa.destroy(self);
    log.info("shut down gracefully.", .{});
}

fn startServer(self: *Self) !void {
    log.info("starting at http://localhost:{d}", .{self.tcp_server.socket.address.getPort()});

    while (!self.shutting_down) {
        const stream = self.tcp_server.accept(self.io) catch |err| return err;
        // TODO: how should I await this thing?
        _ = self.io.async(handleStream, .{ self, stream });
    }
    log.info("shutting down...", .{});
}

fn handleStream(self: *Self, stream: net.Stream) !void {
    var recv_buf: [4096]u8 = undefined;
    var send_buf: [4096]u8 = undefined;
    var reader = stream.reader(self.io, &recv_buf);
    var writer = stream.writer(self.io, &send_buf);
    var http = std.http.Server.init(&reader.interface, &writer.interface);

    // Handle keep-alive: serve multiple requests per connection
    while (http.reader.state == .ready) {
        try self.io.checkCancel();

        var request = http.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                log.err("receiveHead failed: {any}", .{err});
                return;
            },
        };

        handleRequest(self, &request) catch |err| {
            log.err("handleRequest failure: {any}", .{err});
        };
    }
}

fn handleRequest(self: *Self, request: *std.http.Server.Request) !void {
    const io = self.io;
    const path = request.head.target;

    if (mem.eql(u8, path, "/state.json")) {
        var buf: [4096]u8 = undefined;
        var body: []u8 = "";

        {
            try self.state_mutex.lock(io);
            defer self.state_mutex.unlock(io);

            body = try fmt.bufPrint(
                &buf,
                "{f}",
                .{std.json.fmt(self.state, .{})},
            );
        }

        try request.respond(body, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
    } else {
        try self.serveFile(request);
    }
}

/// Tries to serve static file at given path. Responds with 404 if not found.
fn serveFile(self: *Self, request: *std.http.Server.Request) !void {
    const io = self.io;
    var path = request.head.target;

    if (path.len == 0) path = "/";

    if (!mem.startsWith(u8, path, "/")) {
        try request.respond("Malformed path.", .{ .status = .bad_request });
        return;
    }

    if (mem.eql(u8, path, "/")) {
        path = "index.html";
    } else {
        path = path["/".len..];
    }
    log.info("GET {s}", .{path});

    // TODO: unescape/sanitize path?

    var arena_impl = std.heap.ArenaAllocator.init(self.gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const dir = try Io.Dir.cwd().openDir(io, WEB_DIR, .{});
    const blob = dir.readFileAlloc(io, path, arena, .unlimited) catch |err| switch (err) {
        error.FileNotFound => {
            try request.respond("Not found.", .{ .status = .not_found });
            return;
        },
        else => return err,
    };

    try request.respond(blob, .{});
}
