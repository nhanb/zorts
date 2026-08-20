const std = @import("std");
const Io = std.Io;
const State = @import("./State.zig");
const EntryString = State.EntryString;
const MAX_TEXT_LENGTH = State.MAX_TEXT_LENGTH;
const log = std.log.scoped(.Startgg);

pub const INPUTS_FILE = "startgg-inputs.txt";
const DELIMITER = ':';
const API_URL = "https://api.start.gg/gql/alpha";
//const API_URL = "http://localhost:8080"; // python debugsrv.py

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
            \\{s} is malformed. Must be "tournament-slug{c}token".
        ,
            .{ INPUTS_FILE, DELIMITER },
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
    var query_buf: [1024]u8 = undefined;
    var query_writer = Io.Writer.fixed(&query_buf);
    try query_writer.writeAll(
        \\{
        \\  tournament(slug: "
    );
    try query_writer.writeAll(self.tournament_slug.slice());
    try query_writer.writeAll(
        \\") {
        \\    participants(query: {page:
    );
    try query_writer.print(" {d}", .{1}); // TODO do we need to paginate?
    try query_writer.writeAll(
        \\, perPage: 500}) {
        \\      nodes {
        \\        entrants {
        \\          event {
        \\            slug
        \\            name
        \\          }
        \\          team {
        \\            name
        \\          }
        \\        }
        \\        gamerTag
        \\        prefix
        \\        user {
        \\          location {
        \\            country
        \\          }
        \\        }
        \\      }
        \\    }
        \\  }
        \\}
    );

    const request_body = Body{
        .query = query_writer.buffered(),
    };

    var payload_buf: [2048]u8 = undefined;
    var payload_writer = Io.Writer.fixed(&payload_buf);
    var payload_json = std.json.Stringify{ .writer = &payload_writer };
    try payload_json.write(request_body);

    // For some reason std.http.Client.fetch() seems to drop the last 2
    // bytes from the request body, so here I'm appending 2 sacrificial bytes.
    // TODO: See if it's fixed in 0.17, otherwise investigate further.
    // Btw, when start.gg API responds with "POST body not found", it actually
    // means our request body is not valid JSON.
    try payload_writer.writeAll("\n\n");

    const payload = payload_writer.buffered();

    var token_header_buf: [256]u8 = undefined;
    const token_header = try std.fmt.bufPrint(
        &token_header_buf,
        "Bearer {s}",
        .{self.token.slice()},
    );

    var resp_writer = try Io.Writer.Allocating.initCapacity(gpa, 1024 * 8);
    defer resp_writer.deinit();

    var http_client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer http_client.deinit();

    log.info("sending start.gg request...", .{});
    const start = Io.Clock.now(.awake, io);

    const result = try http_client.fetch(.{
        .location = .{ .url = API_URL },
        // Setting .headers here seems to disable the Content-Length
        // header too. No idea why. For now let's just not touch it.
        // TODO: revisit in 0.17.
        // .headers = .{
        //     .user_agent = .{ .override = "ZORTS/0.5" },
        //     .content_type = .{ .override = "application/json" },
        //     .authorization = .{ .override = token_header },
        // },
        .extra_headers = &.{
            .{ .name = "Authorization", .value = token_header },
        },
        .method = .POST,
        .payload = payload,
        .response_writer = &resp_writer.writer,
    });

    const end = std.Io.Clock.now(.awake, io);
    const duration = start.durationTo(end);

    log.info(
        "got status: {d}, body: {d} bytes, took {d}s",
        .{
            result.status,
            resp_writer.writer.buffered().len,
            duration.toSeconds(),
        },
    );
}

const Body = struct {
    query: []const u8,
};
