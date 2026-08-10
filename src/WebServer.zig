const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const mem = std.mem;
const log = std.log;
const State = @import("./State.zig");

const Self = @This();

pub const PORT = 1337;

gpa: std.mem.Allocator,
io: Io,
server: net.Server,
state: *State,
thread: std.Thread,

pub fn init(gpa: std.mem.Allocator, io: Io, state: *State) !*Self {
    var self = try gpa.create(Self);
    self.gpa = gpa;
    self.io = io;
    self.state = state;

    const address: net.IpAddress = .{
        .ip4 = .{
            .bytes = .{ 127, 0, 0, 1 },
            .port = PORT,
        },
    };

    self.server = try address.listen(io, .{ .reuse_address = true });
    log.debug("Starting webserver at http://localhost:{d}", .{address.getPort()});

    //self.thread = try io.concurrent(startServer, .{self});
    self.thread = try .spawn(.{}, startServer, .{self});

    return self;
}

pub fn deinit(self: *Self) void {
    //self.thread.join();
    self.server.deinit(self.io);
    self.gpa.destroy(self);
    log.info("WebServer deinit", .{});
}

fn startServer(self: *Self) !void {
    while (true) {
        log.info("before accept...", .{});
        const stream = self.server.accept(self.io) catch |err| {
            switch (err) {
                error.Canceled => {
                    log.debug("WebServer canceled.", .{});
                    return;
                },
                else => return err,
            }
        };
        // TODO: how should I await this thing?
        log.info("before handleStream...", .{});
        _ = self.io.async(handleStream, .{ self, stream });
    }
}

fn handleStream(self: *Self, stream: net.Stream) !void {
    var arena = std.heap.ArenaAllocator.init(self.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    _ = allocator; // TODO: use this for per-request allocations

    var recv_buf: [4096]u8 = undefined;
    var send_buf: [4096]u8 = undefined;
    var reader = stream.reader(self.io, &recv_buf);
    var writer = stream.writer(self.io, &send_buf);
    var http = std.http.Server.init(&reader.interface, &writer.interface);

    // Handle keep-alive: serve multiple requests per connection
    while (http.reader.state == .ready) {
        log.debug("before checkCancel", .{});
        try self.io.checkCancel();

        log.debug("before receiveHead", .{});
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
    const path = request.head.target;

    if (mem.eql(u8, path, "/")) {
        try request.respond("heeeyo", .{});
    } else if (mem.eql(u8, path, "/state.json")) {
        var buf: [4096]u8 = undefined;
        const body = try std.fmt.bufPrint(
            &buf,
            "{f}",
            .{std.json.fmt(self.state, .{})},
        );
        try request.respond(body, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
    } else {
        try request.respond("nothing to see here", .{ .status = .not_found });
    }
}
