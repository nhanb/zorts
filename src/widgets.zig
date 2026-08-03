const std = @import("std");
const dvui = @import("dvui");
const ButtonWidget = dvui.ButtonWidget;
const Options = dvui.Options;

pub fn button(src: std.builtin.SourceLocation, label_str: []const u8, opts: Options) bool {
    var final_opts = opts;
    final_opts.border = .all(1);

    return dvui.button(src, label_str, .{}, final_opts);
}
