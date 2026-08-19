const std = @import("std");
const dvui = @import("dvui");
const log = std.log.scoped(.State);
const unicode = std.unicode;
const ascii = std.ascii;
const Io = std.Io;
const json = std.json;

pub const MAX_TEXT_LENGTH = 64;

active_tab: Tab = .Main,
title: BoundedString(MAX_TEXT_LENGTH) = .{},
subtitle: BoundedString(MAX_TEXT_LENGTH) = .{},
player1: PlayerState = .{},
player2: PlayerState = .{},

const State = @This();

pub fn loadFile(gpa: std.mem.Allocator, io: Io, path: []const u8) !State {
    var buf: [4096]u8 = undefined;
    const json_slice = Io.Dir.cwd().readFile(io, path, &buf) catch |err| switch (err) {
        error.FileNotFound => {
            log.info("{s} file not found. Starting with empty state.", .{path});
            return .{
                .title = .init("Saigon Cup 2026"),
                .subtitle = .init("FT10"),
                .player1 = .{
                    .team = .init("Team 1"),
                    .country = .init("vn"),
                    .name = .init("Nguyễn-san"),
                    .score = 2,
                },
                .player2 = .{
                    .team = .init("Team 2"),
                    .country = .init("jp"),
                    .name = .init("Shirayukisama"),
                    .score = 1,
                },
            };
        },
        else => return err,
    };

    const parsed = try json.parseFromSlice(State, gpa, json_slice, .{});
    defer parsed.deinit();

    log.info("loading state from {s}", .{path});
    return parsed.value;
}

pub fn saveFile(self: *State, io: Io, path: []const u8) !void {
    var file = try Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var writer = file.writer(io, &buf);

    var stringify = json.Stringify{
        .writer = &writer.interface,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(self);
    try writer.flush();
}

pub const Tab = enum { Main, @"start.gg" };

pub const PlayerState = struct {
    name: BoundedString(MAX_TEXT_LENGTH) = .{},
    team: BoundedString(MAX_TEXT_LENGTH) = .{},
    score: usize = 0,
    country: BoundedString(2) = .{}, // TODO: define an enum?
};

/// Basically the deceased BoundedArray API.
/// (see: https://ziggit.dev/t/std-boundedarray-simple-dropin-replacement)
/// I just want a self-contained State struct with no dangling pointer.
pub fn BoundedString(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buf: [capacity]u8 = @splat(0),
        len: usize = 0,

        pub fn init(init_text: []const u8) Self {
            std.debug.assert(init_text.len <= capacity);

            var string: Self = .{ .len = init_text.len };
            @memcpy(string.buf[0..init_text.len], init_text);
            return string;
        }

        pub fn slice(self: *const Self) []const u8 {
            return self.buf[0..self.len];
        }

        pub fn jsonStringify(self: *const Self, jw: anytype) !void {
            try jw.write(self.slice());
        }

        pub fn jsonParse(gpa: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Self {
            _ = gpa;
            _ = options;
            const token = try source.next();
            switch (token) {
                .string => |str_slice| return .init(str_slice),
                else => return error.UnexpectedToken,
            }
        }

        /// Removes special chars, lowers case, removes Vietnamese diacritics.
        /// Used for lookup.
        pub fn normalized(self: *const Self) Self {
            var result: Self = .{};

            const original = self.slice();
            var index: usize = 0;

            var utf8 = unicode.Utf8View.init(original) catch |err| {
                log.err("failed to read '{s}' as utf8: {any} - skipping normalization", .{ original, err });
                return self.*;
            };
            var iterator = utf8.iterator();

            while (iterator.nextCodepoint()) |codepoint| {
                var cp = codepoint;

                if (cp <= 127) {
                    const char: u8 = @intCast(cp);
                    // if the character is within ASCII range,
                    // we only care about alphanumeric chars:
                    if (!ascii.isAlphanumeric(char)) continue;
                    // lowercase:
                    cp = @intCast(ascii.toLower(char));
                }

                // remove Vietnamese diacritics:
                cp = switch (cp) {
                    'a', 'à', 'á', 'ả', 'ã', 'ạ', 'ă', 'ằ', 'ắ', 'ẳ', 'ẵ', 'ặ', 'â', 'ầ', 'ấ', 'ẩ', 'ẫ', 'ậ' => 'a',
                    'e', 'è', 'é', 'ẻ', 'ẽ', 'ẹ', 'ê', 'ề', 'ế', 'ể', 'ễ', 'ệ' => 'e',
                    'i', 'ì', 'í', 'ỉ', 'ĩ', 'ị' => 'i',
                    'o', 'ò', 'ó', 'ỏ', 'õ', 'ọ', 'ô', 'ồ', 'ố', 'ổ', 'ỗ', 'ộ', 'ơ', 'ờ', 'ớ', 'ở', 'ỡ', 'ợ' => 'o',
                    'u', 'ù', 'ú', 'ủ', 'ũ', 'ụ', 'ư', 'ừ', 'ứ', 'ử', 'ữ', 'ự' => 'u',
                    'y', 'ỳ', 'ý', 'ỷ', 'ỹ', 'ỵ' => 'y',
                    'đ' => 'd',
                    else => cp,
                };

                const bytes_written = unicode.utf8Encode(cp, result.buf[index..]) catch unreachable;
                index += bytes_written;
            }
            result.len = index;

            return result;
        }
    };
}
