const std = @import("std");
const dvui = @import("dvui");
const BoundedArray = @import("./bounded_array.zig").BoundedArray;

pub const MAX_TEXT_LENGTH = 128;
pub const DEFAULT_FONT_SIZE = 10;
pub const COUNTRY_CODE_LENGTH = 2;

active_tab: Tab = .Main,
theme: dvui.Theme = dvui.Theme.builtin.adwaita_light,
title: BoundedArray(u8, MAX_TEXT_LENGTH) = .{},
subtitle: BoundedArray(u8, MAX_TEXT_LENGTH) = .{},
player1: PlayerState = .{},
player2: PlayerState = .{},

pub const Tab = enum { Main, @"start.gg" };

pub const PlayerState = struct {
    name: BoundedArray(u8, MAX_TEXT_LENGTH) = .{},
    team: BoundedArray(u8, MAX_TEXT_LENGTH) = .{},
    score: usize = 0,
    country: BoundedArray(u8, COUNTRY_CODE_LENGTH) = .{}, // TODO: define an enum?
};
