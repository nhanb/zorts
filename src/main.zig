const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const BoundedArray = @import("./bounded_array.zig").BoundedArray;
const State = @import("./State.zig");

const LABEL_WIDTH = 60;

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 500.0, .h = 400.0 },
            .min_size = .{ .w = 500.0 },
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
    try dvui.addFont("Noto", @embedFile("fonts/noto-sans-v42-latin_vietnamese-regular.ttf"), null);
    try dvui.addFont("NotoItalic", @embedFile("fonts/noto-sans-v42-latin_vietnamese-italic.ttf"), null);
    try dvui.addFont("NotoBold", @embedFile("fonts/noto-sans-v42-latin_vietnamese-700.ttf"), null);
    try dvui.addFont("NotoBoldItalic", @embedFile("fonts/noto-sans-v42-latin_vietnamese-700italic.ttf"), null);
    try dvui.addFont("NotoMono", @embedFile("fonts/noto-sans-mono-v37-latin_vietnamese-regular.ttf"), null);
    try dvui.addFont("NotoMonoBold", @embedFile("fonts/noto-sans-mono-v37-latin_vietnamese-700.ttf"), null);

    state.theme.font_body = .find(.{ .family = "Noto", .size = State.DEFAULT_FONT_SIZE });
    state.theme.font_heading = .find(.{ .family = "NotoBold", .size = State.DEFAULT_FONT_SIZE });
    state.theme.font_title = .find(.{ .family = "Noto", .size = State.DEFAULT_FONT_SIZE + 2 });
    state.theme.font_mono = .find(.{ .family = "NotoMono", .size = State.DEFAULT_FONT_SIZE });
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
            .padding = .all(4),
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

        inline for (std.enums.values(State.Tab)) |tab| {
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

                    dvui.labelEx(
                        @src(),
                        "Title",
                        .{},
                        .{ .align_x = 1 },
                        .{
                            .gravity_y = 0.5,
                            .min_size_content = .width(LABEL_WIDTH),
                        },
                    );
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

                    dvui.labelEx(
                        @src(),
                        "Subtitle",
                        .{},
                        .{ .align_x = 1 },
                        .{
                            .gravity_y = 0.5,
                            .min_size_content = .width(LABEL_WIDTH),
                        },
                    );
                    const subtitle_entry = dvui.textEntry(@src(), .{}, .{ .expand = .horizontal });
                    subtitle_entry.deinit();
                }

                //_ = dvui.separator(@src(), .{
                //    .expand = .horizontal,
                //    .margin = .all(10),
                //    .color_fill = .transparent,
                //});

                // Player 1 inputs
                playerInputs(&state.player1, .one);

                //_ = dvui.separator(@src(), .{
                //    .expand = .horizontal,
                //    .margin = .all(10),
                //    .color_fill = .transparent,
                //});

                // Player 2 inputs
                playerInputs(&state.player2, .two);
            },
            .@"start.gg" => {
                dvui.label(@src(), "To be developed...", .{}, .{});
            },
        }
    }

    return dvui.App.Result.ok;
}

fn playerInputs(player: *State.PlayerState, player_num: enum(u8) { one, two }) void {
    const id = @intFromEnum(player_num);

    var p1_hbox = dvui.box(
        @src(),
        .{ .dir = .horizontal },
        .{ .expand = .horizontal, .id_extra = id },
    );
    defer p1_hbox.deinit();
    {
        var p1_vbox = dvui.box(
            @src(),
            .{ .dir = .vertical },
            .{ .expand = .horizontal, .id_extra = id },
        );
        defer p1_vbox.deinit();

        // First row of Player inputs
        {
            var p1_1st_row = dvui.box(
                @src(),
                .{ .dir = .horizontal },
                .{ .expand = .horizontal, .id_extra = id },
            );
            defer p1_1st_row.deinit();

            dvui.labelEx(
                @src(),
                "Player {d}",
                .{@intFromEnum(player_num) + 1},
                .{ .align_x = 1 },
                .{
                    .gravity_y = 0.5,
                    .id_extra = id,
                    .min_size_content = .width(LABEL_WIDTH),
                },
            );

            // Player name input
            const p1_name_entry = dvui.textEntry(
                @src(),
                .{
                    .placeholder = "Name e.g. Bonchan",
                    .text = .{
                        .internal = .{ .limit = player.name.capacity() },
                    },
                },
                .{ .expand = .horizontal, .id_extra = id },
            );
            if (p1_name_entry.text_changed) {
                player.name.clear();
                player.name.appendSliceAssumeCapacity(
                    p1_name_entry.textGet(),
                );
            }
            p1_name_entry.deinit();

            // Player country input
            const p1_country_entry = dvui.textEntry(
                @src(),
                .{
                    .placeholder = "vn",
                    .text = .{
                        .internal = .{ .limit = player.country.capacity() },
                    },
                },
                .{ .max_size_content = .width(30), .id_extra = id },
            );
            if (p1_country_entry.text_changed) {
                player.country.clear();
                player.country.appendSliceAssumeCapacity(
                    p1_country_entry.textGet(),
                );
            }
            p1_country_entry.deinit();

            // Player score input
            const p1_score_entry = dvui.textEntryNumber(
                @src(),
                usize,
                .{ .value = &player.score },
                .{ .max_size_content = .width(30), .id_extra = id },
            );
            _ = p1_score_entry;
        }

        // Second row of Player inputs
        {
            var p1_team_hbox = dvui.box(
                @src(),
                .{ .dir = .horizontal },
                .{ .expand = .horizontal, .id_extra = id },
            );
            defer p1_team_hbox.deinit();

            dvui.labelEx(
                @src(),
                "Team {d}",
                .{@intFromEnum(player_num) + 1},
                .{ .align_x = 1 },
                .{
                    .gravity_y = 0.5,
                    .min_size_content = .width(LABEL_WIDTH),
                },
            );

            // Player team input
            const p1_team_entry = dvui.textEntry(
                @src(),
                .{
                    .text = .{
                        .internal = .{ .limit = player.team.capacity() },
                    },
                },
                .{ .expand = .horizontal, .id_extra = id },
            );
            if (p1_team_entry.text_changed) {
                player.team.clear();
                player.team.appendSliceAssumeCapacity(
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
            .id_extra = id,
            .border = .all(1),
        },
    )) {
        player.score += 1;
    }
}
