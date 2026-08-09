const std = @import("std");
const dvui = @import("dvui");

pub const MAX_TEXT_LENGTH = 64;

active_tab: Tab = .Main,
title: BoundedString(MAX_TEXT_LENGTH) = .{},
subtitle: BoundedString(MAX_TEXT_LENGTH) = .{},
player1: PlayerState = .{},
player2: PlayerState = .{},

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
    };
}
