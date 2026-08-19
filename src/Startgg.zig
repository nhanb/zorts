const std = @import("std");
const Io = std.Io;
const State = @import("./State.zig");
const EntryString = State.EntryString;
const MAX_TEXT_LENGTH = State.MAX_TEXT_LENGTH;
const log = std.log.scoped(.Startgg);

pub const INPUTS_FILE = "startgg-inputs.txt";
const DELIMITER = ':';

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
