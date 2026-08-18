const std = @import("std");
const State = @import("./State.zig");
const BoundedString = State.BoundedString;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const log = std.log.scoped(.PlayerLookup);

pub const PLAYERS_FILE_NAME = "players.csv";

const PlayerLookup = @This();

// TODO Instead of ArrayList, explore a more efficient data structure, say,
// radix tree. It probably doesn't matter for us because our tournaments are...
// not huge.
players: ArrayList(PlayerBio),
query: BoundedString(State.MAX_TEXT_LENGTH) = .{},

pub const PlayerBio = struct {
    name: BoundedString(State.MAX_TEXT_LENGTH),
    country: BoundedString(2),
    team: BoundedString(State.MAX_TEXT_LENGTH),

    // Stuff used for querying:
    matched: bool = false,
    normalized_name: BoundedString(State.MAX_TEXT_LENGTH) = .{},
};

pub fn initFromDisk(gpa: Allocator, io: Io) !PlayerLookup {
    const file = Io.Dir.cwd().openFile(io, PLAYERS_FILE_NAME, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            log.info("{s} file not found => autocompletion is off", .{PLAYERS_FILE_NAME});
            return .{
                .players = try .initCapacity(gpa, 0),
            };
        },
        else => return err,
    };
    defer file.close(io);

    var players = try std.ArrayList(PlayerBio).initCapacity(gpa, 32);

    var file_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &file_buf);
    while (try file_reader.interface.takeDelimiter('\n')) |raw_line| {
        var line = raw_line;
        if (line.len == 0 or mem.eql(u8, line, "\r")) continue;
        if (line[line.len - 1] == '\r') line = line[0 .. line.len - 1];

        // TODO: handle escaping
        // TODO: should I bother handling malformed files?
        var comma_iterator = mem.splitScalar(u8, line, ',');
        var player = PlayerBio{
            .name = .init(comma_iterator.next().?),
            .country = .init(comma_iterator.next().?),
            .team = .init(comma_iterator.next().?),
        };
        player.normalized_name = player.name.normalized();

        try players.append(gpa, player);
    }

    log.info("found {d} players", .{players.items.len});

    return .{ .players = players };
}

pub fn deinit(self: *PlayerLookup, gpa: Allocator) void {
    self.players.deinit(gpa);
    log.info("cleaned up successfully.", .{});
}

pub fn updateQuery(self: *PlayerLookup, query: []const u8) void {
    self.query = .init(query);
    self.query = self.query.normalized();

    for (0..self.players.items.len) |i| {
        const player = &self.players.items[i];
        player.matched =
            if (self.query.len > 0)
                mem.containsAtLeast(
                    u8,
                    player.normalized_name.slice(),
                    1,
                    self.query.slice(),
                )
            else
                false;

        log.info(
            ">> {s} ({s}), {any}",
            .{
                player.name.slice(),
                player.normalized_name.slice(),
                player.matched,
            },
        );
    }
}

pub fn len(self: *PlayerLookup) usize {
    return self.players.items.len;
}

pub fn slice(self: *PlayerLookup) []PlayerBio {
    return self.players.items;
}
