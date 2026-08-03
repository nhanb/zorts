const std = @import("std");
const dvui = @import("dvui");

pub const MAX_TEXT_LENGTH = 64;
pub const DEFAULT_FONT_SIZE = 10;
pub const COUNTRY_CODE_LENGTH = 2;

active_tab: Tab = .Main,
theme: dvui.Theme = dvui.Theme.builtin.adwaita_light,
title: String(MAX_TEXT_LENGTH) = .{},
subtitle: String(MAX_TEXT_LENGTH) = .{},
player1: PlayerState = .{},
player2: PlayerState = .{},

pub const Tab = enum { Main, @"start.gg" };

pub const PlayerState = struct {
    name: String(MAX_TEXT_LENGTH) = .{},
    team: String(MAX_TEXT_LENGTH) = .{},
    score: usize = 0,
    country: [2]u8 = undefined, // TODO: define an enum?
};

pub fn String(comptime capacity: usize) type {
    return struct {
        buf: [capacity]u8 = undefined,
        len: usize = 0,

        pub fn slice(self: *@This()) []u8 {
            return self.buf[0..self.len];
        }
    };
}
