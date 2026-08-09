const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const mem = std.mem;
const log = std.log;

const Self = @This();

pub const PORT = 1337;

gpa: std.mem.Allocator,
io: Io,
server: net.Server,

pub fn init(gpa: std.mem.Allocator, io: Io) !*Self {
    var self = try gpa.create(Self);
    self.gpa = gpa;
    self.io = io;

    const address: net.IpAddress = .{
        .ip4 = .{
            .bytes = .{ 127, 0, 0, 1 },
            .port = PORT,
        },
    };

    self.server = try address.listen(io, .{ .reuse_address = true });

    // TODO: how should I await this thing?
    _ = try io.concurrent(startServer, .{ gpa, io, &self.server });

    return self;
}

pub fn deinit(self: *Self) void {
    self.server.deinit(self.io);
    self.gpa.destroy(self);
    log.info("WebServer deinit", .{});
}

fn startServer(gpa: std.mem.Allocator, io: Io, server: *net.Server) !void {
    while (true) {
        log.debug("Waiting for connection", .{});
        const stream = server.accept(io) catch |err| {
            switch (err) {
                error.Canceled => {
                    log.debug("WebServer cancelled.", .{});
                    return;
                },
                else => return err,
            }
        };
        // TODO: how should I await this thing?
        _ = io.async(handleStream, .{ gpa, io, stream });
    }
}

fn handleStream(gpa: std.mem.Allocator, io: Io, stream: net.Stream) !void {
    _ = gpa;
    var reader_buf: [4096]u8 = undefined;
    var reader = stream.reader(io, &reader_buf);

    var writer_buf: [4096]u8 = undefined;
    var writer = stream.writer(io, &writer_buf);

    var http_server = std.http.Server.init(&reader.interface, &writer.interface);
    var request = http_server.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing => return,
        else => return log.err("failed to receive http request: {t}", .{err}),
    };

    const path = request.head.target;

    if (mem.eql(u8, path, "/")) {
        try request.respond("heeeyo", .{});
    } else {
        try request.respond("not found", .{ .status = .not_found });
    }
}
