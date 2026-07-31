const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const BoundedArray = @import("./bounded_array.zig").BoundedArray;

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "Overly Repetitive Tedius Software (in Zig)",
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

// Globals

var gpa_instance = std.heap.DebugAllocator(.{}){};
const gpa = gpa_instance.allocator();

const Tab = enum { Main, @"start.gg" };

const MAX_TEXT_LENGTH = 128;
const DEFAULT_FONT_SIZE = 10;
const COUNTRY_CODE_LENGTH = 2;

const PlayerState = struct {
    name: BoundedArray(u8, MAX_TEXT_LENGTH) = .{},
    team: BoundedArray(u8, MAX_TEXT_LENGTH) = .{},
    score: usize = 0,
    country: BoundedArray(u8, COUNTRY_CODE_LENGTH) = .{}, // TODO: define an enum?
};

const State = struct {
    active_tab: Tab = .Main,
    theme: dvui.Theme = dvui.Theme.builtin.adwaita_light,
    title: BoundedArray(u8, MAX_TEXT_LENGTH) = .{},
    subtitle: BoundedArray(u8, MAX_TEXT_LENGTH) = .{},
    player1: PlayerState = .{},
    player2: PlayerState = .{},
};
var state: State = .{};

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn appInit(win: *dvui.Window) !void {
    // Choose dark/light theme based on system preferences
    state.theme = switch (win.backend.preferredColorScheme() orelse .light) {
        .light => dvui.Theme.builtin.adwaita_light,
        .dark => dvui.Theme.builtin.adwaita_dark,
    };
    // Custom UI fonts:
    try dvui.addFont("Noto", @embedFile("fonts/noto-sans-v42-latin_vietnamese-regular.woff2"), null);
    try dvui.addFont("NotoItalic", @embedFile("fonts/noto-sans-v42-latin_vietnamese-italic.woff2"), null);
    try dvui.addFont("NotoBold", @embedFile("fonts/noto-sans-v42-latin_vietnamese-700.woff2"), null);
    try dvui.addFont("NotoBoldItalic", @embedFile("fonts/noto-sans-v42-latin_vietnamese-700italic.woff2"), null);
    try dvui.addFont("NotoMono", @embedFile("fonts/noto-sans-mono-v37-latin_vietnamese-regular.woff2"), null);
    try dvui.addFont("NotoMonoBold", @embedFile("fonts/noto-sans-mono-v37-latin_vietnamese-700.woff2"), null);

    state.theme.font_body = .find(.{ .family = "Noto", .size = DEFAULT_FONT_SIZE });
    state.theme.font_heading = .find(.{ .family = "NotoBold", .size = DEFAULT_FONT_SIZE });
    state.theme.font_title = .find(.{ .family = "Noto", .size = DEFAULT_FONT_SIZE + 2 });
    state.theme.font_mono = .find(.{ .family = "NotoMono", .size = DEFAULT_FONT_SIZE });
    state.theme.corner = .square;

    win.themeSet(state.theme);
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

    // Tab headers
    {
        var tabs = dvui.tabs(
            @src(),
            .{ .draw_focus = false },
            .{ .expand = .horizontal },
        );
        defer tabs.deinit();

        inline for (std.enums.values(Tab)) |tab| {
            const active = state.active_tab == tab;

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
                @tagName(tab),
                .{
                    .font = .theme(.body),
                    .corners = .default,
                    .color_fill_hover = if (active) state.theme.color(.window, .fill) else null,
                    .color_fill_press = if (active) state.theme.color(.window, .fill) else null,
                    .margin = .{ .h = if (active) 0 else 1 },
                    .padding = if (active) active_padding else padding,
                    .border = if (active) .{ .x = 1, .y = 1, .w = 1 } else .all(0),
                    .color_border = null,
                },
            )) {
                state.active_tab = tab;
            }
        }
    }

    // Actual tab contents
    {
        var border: dvui.Rect = .all(1);
        border.y = 0;
        var tab_box = dvui.box(@src(), .{}, .{
            .expand = .both,
            .background = true,
            .style = .window,
            .border = border,
            .role = .tab_panel,
        });
        defer tab_box.deinit();

        switch (state.active_tab) {
            .Main => {
                // Title input
                {
                    var title_hbox = dvui.box(
                        @src(),
                        .{ .dir = .horizontal },
                        .{ .expand = .horizontal },
                    );
                    defer title_hbox.deinit();

                    dvui.label(@src(), "Title", .{}, .{ .gravity_y = 0.5 });
                    const title_entry = dvui.textEntry(@src(), .{}, .{ .expand = .horizontal });
                    title_entry.deinit();
                }

                // Subtitle input
                {
                    var subtitle_hbox = dvui.box(
                        @src(),
                        .{ .dir = .horizontal },
                        .{ .expand = .horizontal },
                    );
                    defer subtitle_hbox.deinit();

                    dvui.label(@src(), "Subtitle", .{}, .{ .gravity_y = 0.5 });
                    const subtitle_entry = dvui.textEntry(@src(), .{}, .{ .expand = .horizontal });
                    subtitle_entry.deinit();
                }

                _ = dvui.separator(@src(), .{
                    .expand = .horizontal,
                    .margin = .all(5),
                    .color_fill = .transparent,
                });

                // Player 1 inputs
                {
                    var p1_hbox = dvui.box(
                        @src(),
                        .{ .dir = .horizontal },
                        .{ .expand = .horizontal },
                    );
                    defer p1_hbox.deinit();
                    {
                        var p1_vbox = dvui.box(
                            @src(),
                            .{ .dir = .vertical },
                            .{ .expand = .horizontal },
                        );
                        defer p1_vbox.deinit();

                        // First row of Player 1 inputs
                        {
                            var p1_1st_row = dvui.box(
                                @src(),
                                .{ .dir = .horizontal },
                                .{ .expand = .horizontal },
                            );
                            defer p1_1st_row.deinit();

                            dvui.label(@src(), "Player 1", .{}, .{ .gravity_y = 0.5 });

                            // Player 1 name input
                            const p1_name_entry = dvui.textEntry(
                                @src(),
                                .{
                                    .placeholder = "Name e.g. Bonchan",
                                    .text = .{
                                        .internal = .{ .limit = state.player1.name.capacity() },
                                    },
                                },
                                .{ .expand = .horizontal },
                            );
                            if (p1_name_entry.text_changed) {
                                state.player1.name.clear();
                                state.player1.name.appendSliceAssumeCapacity(
                                    p1_name_entry.textGet(),
                                );
                            }
                            p1_name_entry.deinit();

                            // Player 1 country input
                            const p1_country_entry = dvui.textEntry(
                                @src(),
                                .{
                                    .placeholder = "vn",
                                    .text = .{
                                        .internal = .{ .limit = state.player1.country.capacity() },
                                    },
                                },
                                .{ .max_size_content = .width(30) },
                            );
                            if (p1_country_entry.text_changed) {
                                state.player1.country.clear();
                                state.player1.country.appendSliceAssumeCapacity(
                                    p1_country_entry.textGet(),
                                );
                            }
                            p1_country_entry.deinit();

                            // Player 1 score input
                            const p1_score_entry = dvui.textEntryNumber(
                                @src(),
                                usize,
                                .{ .value = &state.player1.score },
                                .{ .max_size_content = .width(30) },
                            );
                            _ = p1_score_entry;
                        }

                        // Second row of Player 1 inputs
                        {
                            var p1_team_hbox = dvui.box(
                                @src(),
                                .{ .dir = .horizontal },
                                .{ .expand = .horizontal },
                            );
                            defer p1_team_hbox.deinit();

                            dvui.label(@src(), "Team 1", .{}, .{ .gravity_y = 0.5 });

                            // Player 1 team input
                            const p1_team_entry = dvui.textEntry(
                                @src(),
                                .{
                                    .text = .{
                                        .internal = .{ .limit = state.player1.team.capacity() },
                                    },
                                },
                                .{ .expand = .horizontal },
                            );
                            if (p1_team_entry.text_changed) {
                                state.player1.team.clear();
                                state.player1.team.appendSliceAssumeCapacity(
                                    p1_team_entry.textGet(),
                                );
                            }
                            p1_team_entry.deinit();
                        }
                    }

                    if (dvui.button(
                        @src(),
                        "Win",
                        .{},
                        .{
                            .expand = .vertical,
                            .padding = .all(15),
                        },
                    )) {
                        state.player1.score += 1;
                    }
                }

                _ = dvui.separator(@src(), .{
                    .expand = .horizontal,
                    .margin = .all(5),
                    .color_fill = .transparent,
                });
            },
            .@"start.gg" => {
                dvui.label(@src(), "To be developed...", .{}, .{});
            },
        }
    }

    return dvui.App.Result.ok;
}
