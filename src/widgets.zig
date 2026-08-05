const std = @import("std");
const dvui = @import("dvui");
const ButtonWidget = dvui.ButtonWidget;
const Options = dvui.Options;
const TextEntryWidget = dvui.TextEntryWidget;
const State = @import("./State.zig");

const button_default_opts: Options = .{
    .border = .all(1),
    .corners = .round(3),
    .padding = .{ .x = 15, .w = 15, .y = 6, .h = 7 },
};

pub fn button(src: std.builtin.SourceLocation, label_str: []const u8, opts: Options) bool {
    const options = button_default_opts.override(opts);
    return dvui.button(src, label_str, .{}, options);
}

pub fn textEntry(
    src: std.builtin.SourceLocation,
    string_val: anytype,
    init_opts: TextEntryWidget.InitOptions,
    opts: Options,
) void {
    var iopts = init_opts;
    iopts.text = .{ .buffer = &string_val.buf };

    const entry = dvui.textEntry(src, iopts, opts);
    if (entry.text_changed) {
        string_val.len = entry.len;
    }
    entry.deinit();
}
