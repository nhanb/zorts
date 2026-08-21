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
    applied_text: []const u8,
    init_options: TextEntryWidget.InitOptions,
    options: Options,
) *TextEntryWidget {
    var init_opts = init_options;
    init_opts.text = .{ .buffer = &string_val.buf };

    var opts = options;
    if (!std.mem.eql(u8, string_val.slice(), applied_text)) {
        opts.color_fill = dvui.themeGet().app1.fill;
    }

    const entry = dvui.textEntry(src, init_opts, opts);
    if (entry.text_changed) {
        string_val.len = entry.len;
    }

    return entry;
}

pub fn textEntryNumber(
    src: std.builtin.SourceLocation,
    number: *usize,
    applied_number: usize,
    id_extra: ?usize,
) void {
    _ = dvui.textEntryNumber(
        src,
        usize,
        .{ .value = number },
        .{
            .max_size_content = .width(30),
            .id_extra = id_extra,
            .color_fill = if (number.* != applied_number)
                dvui.themeGet().app1.fill
            else
                null,
        },
    );
}
