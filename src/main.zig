const std = @import("std");
const log = std.log;
const builtin = @import("builtin");
const dvui = @import("dvui");
const State = @import("./State.zig");
const widgets = @import("./widgets.zig");

const LABEL_WIDTH = 60;

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 500, .h = 400 },
            .min_size = .{ .w = 500, .h = 380 },
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
                    widgets.textEntry(
                        @src(),
                        &state.title,
                        .{},
                        .{ .expand = .horizontal },
                    );
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
                    widgets.textEntry(
                        @src(),
                        &state.subtitle,
                        .{ .text = .{ .buffer = &state.subtitle.buf } },
                        .{ .expand = .horizontal },
                    );
                }

                // Player 1 inputs
                playerInputs(&state.player1, .one);

                // Player 2 inputs
                playerInputs(&state.player2, .two);

                // Bottom buttons group
                {
                    const buttons_hbox = dvui.box(
                        @src(),
                        .{ .dir = .horizontal },
                        .{ .margin = .{ .y = 10 }, .gravity_x = 0.5 },
                    );
                    defer buttons_hbox.deinit();

                    if (widgets.button(@src(), "Apply", .{})) {
                        // TODO
                    }

                    if (widgets.button(@src(), "Discard", .{})) {
                        // TODO
                    }

                    if (widgets.button(@src(), "Reset scores", .{})) {
                        // TODO
                    }

                    if (widgets.button(@src(), "Swap players", .{})) {
                        const tmp = state.player1;
                        state.player1 = state.player2;
                        state.player2 = tmp;
                    }
                }

                // Instruction message
                {
                    const hbox = dvui.box(
                        @src(),
                        .{ .dir = .horizontal },
                        .{ .gravity_y = 1 },
                    );
                    defer hbox.deinit();

                    dvui.label(
                        @src(),
                        "Point your OBS browser source to",
                        .{},
                        .{},
                    );
                    dvui.link(
                        @src(),
                        .{
                            .label = "http://localhost:1337",
                            .url = "http://localhost:1337",
                        },
                        .{ .margin = .{ .x = -6 } },
                    );
                }
            },
            .@"start.gg" => {
                dvui.label(@src(), "To be developed...", .{}, .{});
            },
        }
    }

    return dvui.App.Result.ok;
}

fn playerInputs(player: *State.PlayerState, player_num: enum(u8) { one, two }) void {
    //log.info("Titles: '{s}', '{s}'", .{ state.title.slice(), state.subtitle.slice() });
    //log.info("Player {d}: '{s}'", .{ @intFromEnum(player_num) + 1, player.team.slice() });

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
            widgets.textEntry(
                @src(),
                &player.name,
                .{ .placeholder = "Name e.g. Bonchan" },
                .{ .expand = .horizontal, .id_extra = id },
            );

            // Player country input
            widgets.textEntry(
                @src(),
                &player.country,
                .{ .placeholder = "vn" },
                .{ .max_size_content = .width(30), .id_extra = id },
            );

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
            widgets.textEntry(
                @src(),
                &player.team,
                .{},
                .{ .expand = .horizontal, .id_extra = id },
            );
        }
    }

    if (widgets.button(
        @src(),
        "Win",
        .{
            .expand = .vertical,
            .padding = .all(15),
            .id_extra = id,
        },
    )) {
        player.score += 1;
    }
}
