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

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn appInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;

    // Add your own bundled font files...:
    // try dvui.addFont("NOTO", @embedFile("../src/fonts/NotoSansKR-Regular.ttf"), null);

    // If you want a custom theme use something like this:
    // const theme = switch (win.backend.preferredColorScheme() orelse .light) {
    //     .light => dvui.Theme.builtin.adwaita_light,
    //     .dark => dvui.Theme.builtin.adwaita_dark,
    // };
    // win.themeSet(theme);
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn appDeinit(win: *dvui.Window) void {
    _ = win;
}

// Run each frame to do normal UI
pub fn appFrame() !dvui.App.Result {
    {
        // Here's the dvui example content, replace/modify with your stuff

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

    // only shows the demo if dvui.Examples.show_demo_window is true
    // .full -> .lite or comment out to speed up compile times
    dvui.Examples.demo(.full);

    return .ok;
}

const Tab = enum { Main, @"start.gg" };

const margin = 4;

pub fn content() ?dvui.App.Result {
    var tbox = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
    defer tbox.deinit();

    {
        var tabs = dvui.tabs(@src(), .{}, .{
            .expand = .horizontal,
            .margin = dvui.Rect{ .y = margin, .x = margin, .w = margin, .h = 0 },
        });
        defer tabs.deinit();

        inline for (std.meta.fieldNames(Tab), 0..) |tab_name, i| {
            // easy label only
            if (tabs.addTabLabel(
                active_tab == i,
                tab_name,
                .{ .font = .{ .weight = .normal } },
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
            .margin = dvui.Rect{ .y = 0, .x = margin, .w = margin, .h = margin },
            //.color_fill = .blue,
        });
        defer vbox3.deinit();

        dvui.labelEx(@src(), "This is tab {d}", .{active_tab}, .{ .align_x = 0.5, .align_y = 0.5 }, .{ .expand = .horizontal });
        if (active_tab == 3) {
            dvui.icon(@src(), "icon", dvui.entypo.aircraft, .{}, .{ .min_size_content = .all(30), .gravity_x = 0.5 });
        }
    }

    return dvui.App.Result.ok;
}
