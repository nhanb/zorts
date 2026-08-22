const std = @import("std");
const State = @import("./State.zig");
const EntryString = State.EntryString;
const CountryString = State.CountryString;
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
query: EntryString = .{},

pub const PlayerBio = struct {
    name: EntryString,
    country: CountryString,
    team: EntryString,

    // Stuff used for querying:
    matched: bool = false,
    normalized_name: EntryString = .{},
};

/// Tries to read player bios from csv file, falling back to an empty lookup
/// table, effectively disabling autocompletion.
pub fn init(gpa: Allocator, io: Io) PlayerLookup {
    return initFromDisk(gpa, io) catch |err| blk: {
        log.err(
            "unexpected error while loading {s}: {any} => autocompletion is off",
            .{ PLAYERS_FILE_NAME, err },
        );
        break :blk initEmpty(gpa);
    };
}

pub fn initEmpty(gpa: Allocator) PlayerLookup {
    return .{
        .players = ArrayList(PlayerBio).initCapacity(gpa, 0) catch unreachable,
    };
}

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

        // TODO: handle escaping?
        var comma_iterator = mem.splitScalar(u8, line, ',');
        const maybe_name = comma_iterator.next();
        const maybe_country = comma_iterator.next();
        const maybe_team = comma_iterator.next();
        if (maybe_name == null or maybe_country == null or maybe_team == null) {
            log.err("skipping invalid csv line: {s}", .{line});
            continue;
        }
        // TODO: should I skip lines where values are too long, or should I
        // truncate them? Right now we let the assert in BoundedString.init()
        // crash the whole thing.
        var player = PlayerBio{
            .name = .init(maybe_name.?),
            .country = .init(maybe_country.?),
            .team = .init(maybe_team.?),
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
                true;
    }
}

pub fn len(self: *PlayerLookup) usize {
    return self.players.items.len;
}

pub fn slice(self: *PlayerLookup) []PlayerBio {
    return self.players.items;
}

pub fn saveToDisk(self: *PlayerLookup, io: Io) !void {
    var file = try Io.Dir.cwd().createFile(io, PLAYERS_FILE_NAME, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var writer = file.writer(io, &buf);

    for (self.players.items) |player| {
        // using Windows-style newline to make sure normal people can edit the
        // file in any editor (e.g. notepad). Unix-like people probably use
        // decent editors that work seamlessly with either style anyway.
        try writer.interface.print("{s},{s},{s}\r\n", .{
            player.name.slice(),
            player.country.slice(),
            player.team.slice(),
        });
    }
    try writer.interface.flush();
    log.info(
        "saved {d} players to {s}",
        .{ self.players.items.len, PLAYERS_FILE_NAME },
    );
}
