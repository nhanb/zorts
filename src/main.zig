const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "DVUI App Example",
            //.icon = window_icon_png,
            .window_init_options = .{
                // Could set a default theme here
                // .theme = dvui.Theme.builtin.dracula,
            },
        },
    },
    .frameFn = appFrame,
    .initFn = appInit,
    .deinitFn = appDeinit,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var orig_content_scale: f32 = 1.0;
var warn_on_quit: bool = false;
var warn_on_quit_closing: bool = false;
var extra_os_win: bool = false;

var active_tab: usize = 0;

var theme = dvui.Theme.builtin.adwaita_light;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn appInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;

    // Add your own bundled font files...:
    try dvui.addFont("Noto", @embedFile("fonts/noto-sans-v42-latin_vietnamese-regular.woff2"), null);
    try dvui.addFont("NotoItalic", @embedFile("fonts/noto-sans-v42-latin_vietnamese-italic.woff2"), null);
    try dvui.addFont("NotoBold", @embedFile("fonts/noto-sans-v42-latin_vietnamese-700.woff2"), null);
    try dvui.addFont("NotoBoldItalic", @embedFile("fonts/noto-sans-v42-latin_vietnamese-700italic.woff2"), null);
    try dvui.addFont("NotoMono", @embedFile("fonts/noto-sans-mono-v37-latin_vietnamese-regular.woff2"), null);
    try dvui.addFont("NotoMonoBold", @embedFile("fonts/noto-sans-mono-v37-latin_vietnamese-700.woff2"), null);

    theme = switch (win.backend.preferredColorScheme() orelse .light) {
        .light => dvui.Theme.builtin.adwaita_light,
        .dark => dvui.Theme.builtin.adwaita_dark,
    };

    const default_font_size = 12;
    theme.font_body = .find(.{ .family = "Noto", .size = default_font_size });
    theme.font_heading = .find(.{ .family = "NotoBold", .size = default_font_size });
    theme.font_title = .find(.{ .family = "Noto", .size = default_font_size + 2 });
    theme.font_mono = .find(.{ .family = "NotoMono", .size = default_font_size });
    theme.corner = .square;

    win.themeSet(theme);
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn appDeinit(win: *dvui.Window) void {
    _ = win;
}

// Run each frame to do normal UI
pub fn appFrame() !dvui.App.Result {
    {
        var scaler = dvui.scale(
            @src(),
            .{ .scale = &dvui.currentWindow().content_scale, .pinch_zoom = .global },
            .{ .rect = .cast(dvui.windowRect()) },
        );
        scaler.deinit();

        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
        defer scroll.deinit();

        if (content()) |res| return res;
    }

    return .ok;
}

const Tab = enum { Main, @"start.gg" };

pub fn content() ?dvui.App.Result {
    var tbox = dvui.box(
        @src(),
        .{ .dir = .vertical },
        .{
            .expand = .both,
            .margin = .all(0),
            .padding = .all(2),
        },
    );
    defer tbox.deinit();

    {
        var tabs = dvui.tabs(
            @src(),
            .{ .draw_focus = false },
            .{ .expand = .horizontal },
        );
        defer tabs.deinit();

        inline for (std.meta.fieldNames(Tab), 0..) |tab_name, i| {
            const active = active_tab == i;

            const padding: dvui.Rect = .{
                .x = 15,
                .y = 2,
                .w = 15,
                .h = 3,
            };
            const active_padding: dvui.Rect = .{
                .x = padding.x - 1,
                .y = padding.y - 1,
                .w = padding.w - 1,
                .h = padding.h + 1,
            };

            if (tabs.addTabLabel(
                active,
                tab_name,
                .{
                    .font = .theme(.body),
                    .corners = .default,
                    .color_fill_hover = if (active) theme.color(.window, .fill) else null,
                    .color_fill_press = if (active) theme.color(.window, .fill) else null,
                    .margin = .{ .h = if (active) 0 else 1 },
                    .padding = if (active) active_padding else padding,
                    .border = if (active) .{ .x = 1, .y = 1, .w = 1 } else .all(0),
                    .color_border = null,
                },
            )) {
                active_tab = i;
            }
        }
    }

    {
        var border: dvui.Rect = .all(1);
        border.y = 0;
        var vbox3 = dvui.box(@src(), .{}, .{
            .expand = .both,
            .background = true,
            .style = .window,
            .border = border,
            .role = .tab_panel,
        });
        defer vbox3.deinit();

        dvui.labelEx(@src(), "This is tab {d}", .{active_tab}, .{ .align_x = 0.5, .align_y = 0.5 }, .{ .expand = .horizontal });
        if (active_tab == 3) {
            dvui.icon(@src(), "icon", dvui.entypo.aircraft, .{}, .{ .min_size_content = .all(30), .gravity_x = 0.5 });
        }
    }

    return dvui.App.Result.ok;
}
