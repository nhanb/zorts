const std = @import("std");
const dvui = @import("dvui");
const ButtonWidget = dvui.ButtonWidget;
const Options = dvui.Options;
const TextEntryWidget = dvui.TextEntryWidget;
const State = @import("./State.zig");

pub fn button(src: std.builtin.SourceLocation, label_str: []const u8, opts: Options) bool {
    var final_opts = opts;
    final_opts.border = .all(1);

    return dvui.button(src, label_str, .{}, final_opts);
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
