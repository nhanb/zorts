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

    // TODO: how should I await this thing?
    _ = try io.concurrent(startServer, .{self});

    return self;
}

pub fn deinit(self: *Self) void {
    self.server.deinit(self.io);
    self.gpa.destroy(self);
    log.info("WebServer deinit", .{});
}

fn startServer(self: *Self) !void {
    while (true) {
        const stream = self.server.accept(self.io) catch |err| {
            switch (err) {
                error.Canceled => {
                    log.debug("WebServer cancelled.", .{});
                    return;
                },
                else => return err,
            }
        };
        // TODO: how should I await this thing?
        _ = self.io.async(handleStream, .{ self, stream });
    }
}

fn handleStream(self: *Self, stream: net.Stream) !void {
    var reader_buf: [4096]u8 = undefined;
    var reader = stream.reader(self.io, &reader_buf);

    var writer_buf: [4096]u8 = undefined;
    var writer = stream.writer(self.io, &writer_buf);

    var http_server = std.http.Server.init(&reader.interface, &writer.interface);
    var request = http_server.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing => return,
        else => return log.err("failed to receive http request: {t}", .{err}),
    };

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
