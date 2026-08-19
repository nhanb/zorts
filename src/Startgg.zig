const std = @import("std");
const Io = std.Io;
const State = @import("./State.zig");
const EntryString = State.EntryString;
const MAX_TEXT_LENGTH = State.MAX_TEXT_LENGTH;
const log = std.log.scoped(.Startgg);

pub const INPUTS_FILE = "startgg-inputs.txt";
const DELIMITER = ':';
const API_HOST = "api.start.gg";
const API_PATH = "/gql/alpha";
const API_URL = "https://api.start.gg/gql/alpha";

const Self = @This();

tournament_slug: EntryString = .{},
token: EntryString = .{},

pub fn loadFile(io: Io) Self {
    var buf: [4096]u8 = undefined;
    const slice = Io.Dir.cwd().readFile(io, INPUTS_FILE, &buf) catch return .{};
    var parts = std.mem.splitScalar(u8, slice, DELIMITER);

    const tournament_slug = parts.next();
    const token = parts.next();

    if (tournament_slug == null or token == null) {
        log.err(
            "{s} is malformed. Must be \"tournament_slug:token\"",
            .{INPUTS_FILE},
        );
        return .{};
    }

    return .{
        .token = .init(token.?),
        .tournament_slug = .init(tournament_slug.?),
    };
}

pub fn writeFile(self: *Self, io: Io) !void {
    const file = try Io.Dir.cwd().createFile(io, INPUTS_FILE, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var writer = file.writer(io, &buf);

    try writer.interface.writeAll(self.tournament_slug.slice());
    try writer.interface.writeByte(DELIMITER);
    try writer.interface.writeAll(self.token.slice());

    try writer.flush();
}

pub fn importTournament(self: *Self, gpa: std.mem.Allocator, io: Io) !void {
    var http_client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer http_client.deinit();

    var resp_writer = Io.Writer.Allocating.init(gpa);
    defer resp_writer.deinit();

    var token_buf: [256]u8 = undefined;
    const result = try http_client.fetch(.{
        .method = .GET,
        .location = .{ .url = API_URL },
        .response_writer = &resp_writer.writer,
        .extra_headers = &.{
            .{ .name = "User-Agent", .value = "ZORTS/0.5" },
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Authorization", .value = try std.fmt.bufPrint(
                &token_buf,
                "Bearer {s}",
                .{self.token.slice()},
            ) },
        },
    });
    log.info(
        "status: {d}, body: {s}",
        .{ result.status, resp_writer.writer.buffered() },
    );
}
