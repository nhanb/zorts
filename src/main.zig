const std = @import("std");
const log = std.log;
const builtin = @import("builtin");
const dvui = @import("dvui");
const State = @import("./State.zig");
const widgets = @import("./widgets.zig");
const WebServer = @import("./WebServer.zig");
const PlayerLookup = @import("./PlayerLookup.zig");
const Startgg = @import("./Startgg.zig");

const LABEL_WIDTH = 60;
const DEFAULT_FONT_SIZE = 10;

const STATE_FILE = "state.json";
const APPLIED_STATE_FILE = "state-applied.json";

var theme: dvui.Theme = dvui.Theme.builtin.adwaita_light;

const ZORTS_APPLY = "zorts_apply";

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 500, .h = 380 },
            .min_size = .{ .w = 500, .h = 380 },
            .title = "Overly Repetitive Tedious Software",
            .icon = @embedFile("./icons/zorts.png"),
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

/// applied_state is accessed in 3 ways:
/// 1. "Apply" button:     WRITE from main thread
/// 2. Text entry widgets: READ from main thread
/// 3. Web server:         READ from web server thread
/// We only need to use the mutex on 1 & 3,
/// because 2 never happens concurrently with 1.
var applied_state = State{};
var applied_state_mutex: std.Io.Mutex = .init;

var threaded_io: std.Io.Threaded = undefined;
var web_server: *WebServer = undefined;

var player_lookup: PlayerLookup = undefined;
var startgg: Startgg = undefined;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn appInit(win: *dvui.Window) !void {
    threaded_io = .init(gpa, .{});
    const io = threaded_io.io();

    state = try State.loadFile(gpa, io, STATE_FILE);
    applied_state = try State.loadFile(gpa, io, APPLIED_STATE_FILE);

    // Init web server in another thread
    web_server = try .init(
        gpa,
        io,
        &applied_state,
        &applied_state_mutex,
    );

    // Load player list from disk if file exists
    player_lookup = .init(gpa, io);

    // Load start.gg tab inputs if file exists
    startgg = .loadFile(io);

    // Choose dark/light theme based on system preferences
    theme = switch (win.backend.preferredColorScheme() orelse .light) {
        .light => blk: {
            var t = dvui.Theme.builtin.adwaita_light;
            // Diff background color:
            t.app1.fill = dvui.Color{ .r = 218, .g = 251, .b = 225 };
            break :blk t;
        },
        .dark => blk: {
            var t = dvui.Theme.builtin.adwaita_dark;
            // Diff background color:
            t.app1.fill = dvui.Color{ .r = 0x20, .g = 0x47, .b = 0x0b };
            break :blk t;
        },
    };

    try win.keybinds.put(gpa, ZORTS_APPLY, switch (builtin.target.os.tag) {
        .macos => .{ .command = true, .key = .enter },
        else => .{ .control = true, .key = .enter },
    });

    // Custom UI fonts:
    try dvui.addFont("Noto", @embedFile("fonts/noto-sans-v42-latin_vietnamese-regular.ttf"), null);
    try dvui.addFont("NotoItalic", @embedFile("fonts/noto-sans-v42-latin_vietnamese-italic.ttf"), null);
    try dvui.addFont("NotoBold", @embedFile("fonts/noto-sans-v42-latin_vietnamese-700.ttf"), null);
    try dvui.addFont("NotoBoldItalic", @embedFile("fonts/noto-sans-v42-latin_vietnamese-700italic.ttf"), null);
    try dvui.addFont("NotoMono", @embedFile("fonts/noto-sans-mono-v37-latin_vietnamese-regular.ttf"), null);
    try dvui.addFont("NotoMonoBold", @embedFile("fonts/noto-sans-mono-v37-latin_vietnamese-700.ttf"), null);

    theme.font_body = .find(.{ .family = "Noto", .size = DEFAULT_FONT_SIZE });
    theme.font_heading = .find(.{ .family = "NotoBold", .size = DEFAULT_FONT_SIZE });
    theme.font_title = .find(.{ .family = "Noto", .size = DEFAULT_FONT_SIZE + 2 });
    theme.font_mono = .find(.{ .family = "NotoMono", .size = DEFAULT_FONT_SIZE });
    theme.corner = .square;

    win.themeSet(theme);
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn appDeinit(win: *dvui.Window) void {
    _ = win;
    const io = threaded_io.io();
    web_server.deinit();
    player_lookup.deinit(gpa);
    state.saveFile(io, STATE_FILE) catch unreachable;
    applied_state.saveFile(io, APPLIED_STATE_FILE) catch unreachable;
    startgg.writeFile(io) catch unreachable;
}

// Run each frame to do normal UI
pub fn appFrame() !dvui.App.Result {

    // Handle keyboard shortcuts
    const evts = dvui.events();
    for (evts) |*e| {
        switch (e.evt) {
            .key => |key| {
                if (key.action == .down) {
                    if (key.matchBind(ZORTS_APPLY)) {
                        apply();
                    }
                }
            },
            else => {},
        }
    }

    // Actual GUI
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
                    .color_fill_hover = if (active) theme.color(.window, .fill) else null,
                    .color_fill_press = if (active) theme.color(.window, .fill) else null,
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
                    const title_entry = widgets.textEntry(
                        @src(),
                        &state.title,
                        applied_state.title.slice(),
                        .{},
                        .{ .expand = .horizontal },
                    );
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
                    var subtitle_entry = widgets.textEntry(
                        @src(),
                        &state.subtitle,
                        applied_state.subtitle.slice(),
                        .{ .text = .{ .buffer = &state.subtitle.buf } },
                        .{ .expand = .horizontal },
                    );
                    subtitle_entry.deinit();
                }

                // Player 1 inputs
                playerInputs(&state.player1, &applied_state.player1, .one);

                // Player 2 inputs
                playerInputs(&state.player2, &applied_state.player2, .two);

                // Bottom buttons group
                {
                    const buttons_hbox = dvui.box(
                        @src(),
                        .{ .dir = .horizontal },
                        .{ .margin = .{ .y = 10 }, .gravity_x = 0.5 },
                    );
                    defer buttons_hbox.deinit();

                    if (widgets.button(@src(), "Apply", .{})) {
                        apply();
                    }

                    if (widgets.button(@src(), "Discard", .{})) {
                        state = applied_state;
                    }

                    if (widgets.button(@src(), "Reset scores", .{})) {
                        state.player1.score = 0;
                        state.player2.score = 0;
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
                    const url = std.fmt.comptimePrint(
                        "http://localhost:{d}/",
                        .{WebServer.PORT},
                    );
                    dvui.link(
                        @src(),
                        .{ .label = url, .url = url },
                        .{ .margin = .{ .x = -6 } },
                    );
                }
            },
            .@"start.gg" => {
                const STARTGG_LABEL_WIDTH = 90;
                {
                    var hbox = dvui.box(
                        @src(),
                        .{ .dir = .horizontal },
                        .{ .expand = .horizontal },
                    );
                    defer hbox.deinit();

                    dvui.labelEx(
                        @src(),
                        "Tournament",
                        .{},
                        .{ .align_x = 1 },
                        .{
                            .gravity_y = 0.5,
                            .min_size_content = .width(STARTGG_LABEL_WIDTH),
                        },
                    );

                    // Tournament slug input
                    const tournament_slug_entry = widgets.textEntry(
                        @src(),
                        &startgg.tournament_slug,
                        startgg.tournament_slug.slice(),
                        .{},
                        .{ .expand = .horizontal },
                    );
                    tournament_slug_entry.deinit();
                }
                {
                    var hbox = dvui.box(
                        @src(),
                        .{ .dir = .horizontal },
                        .{ .expand = .horizontal },
                    );
                    defer hbox.deinit();

                    dvui.labelEx(
                        @src(),
                        "Token",
                        .{},
                        .{ .align_x = 1 },
                        .{
                            .gravity_y = 0.5,
                            .min_size_content = .width(STARTGG_LABEL_WIDTH),
                        },
                    );

                    // Token input
                    const token_entry = widgets.textEntry(
                        @src(),
                        &startgg.token,
                        startgg.token.slice(),
                        .{ .password_char = "*" },
                        .{ .expand = .horizontal },
                    );
                    token_entry.deinit();
                }
                {
                    var hbox = dvui.box(
                        @src(),
                        .{ .dir = .horizontal },
                        .{ .expand = .horizontal },
                    );
                    defer hbox.deinit();

                    dvui.labelEx(
                        @src(),
                        "",
                        .{},
                        .{ .align_x = 1 },
                        .{
                            .gravity_y = 0.5,
                            .min_size_content = .width(STARTGG_LABEL_WIDTH),
                        },
                    );

                    if (widgets.button(@src(), "Import", .{})) player_import: {
                        // TODO don't freeze the UI during http request
                        const num_players = startgg.importTournament(
                            gpa,
                            threaded_io.io(),
                            &player_lookup,
                        ) catch |err| {
                            var toast_buf: [1024]u8 = undefined;
                            dvui.toast(
                                @src(),
                                .{
                                    .message = std.fmt.bufPrint(
                                        &toast_buf,
                                        "start.gg import error: {any}",
                                        .{err},
                                    ) catch unreachable,
                                },
                            );
                            break :player_import;
                        };
                        var toast_buf: [64]u8 = undefined;
                        dvui.toast(
                            @src(),
                            .{
                                .message = std.fmt.bufPrint(
                                    &toast_buf,
                                    "{d} players imported.",
                                    .{num_players},
                                ) catch unreachable,
                            },
                        );
                    }
                }
            },
        }
    }

    return dvui.App.Result.ok;
}

fn playerInputs(
    player: *State.PlayerState,
    applied_player: *State.PlayerState,
    player_num: enum(u8) { one, two },
) void {
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
            // TODO: this one doesn't use widgets.textEntry() but wrangles
            // dvui.TextEntryWidget directly to be able to setup suggestions.
            // But then it has to duplicate widgets.textEntry()'s diff detection
            // and BoundedString len synchronization. Not great. Try to refactor
            // these things somehow.
            {
                var name_entry: dvui.TextEntryWidget = undefined;
                var opts: dvui.Options = .{ .expand = .horizontal, .id_extra = id };
                if (!std.mem.eql(u8, player.name.slice(), applied_player.name.slice())) {
                    opts.color_fill = dvui.themeGet().app1.fill;
                }
                name_entry.init(
                    @src(),
                    .{ .text = .{ .buffer = &player.name.buf } },
                    opts,
                );

                var sug = dvui.suggestion(&name_entry, .{ .open_on_text_change = true });

                // dvui.suggestion processes events so text entry should be updated
                if (name_entry.text_changed) {
                    player.name.len = name_entry.len;
                    player_lookup.updateQuery(name_entry.getText());
                }

                if (sug.dropped()) {
                    for (player_lookup.slice()) |player_bio| {
                        if (!player_bio.matched) continue;
                        const name = player_bio.name.slice();
                        if (sug.addChoiceLabel(name)) {
                            name_entry.textSet(name, false);
                            player.name = player_bio.name;
                            player.country = player_bio.country;
                            player.team = player_bio.team;
                            player_lookup.updateQuery(name_entry.getText());
                            sug.close();
                        }
                    }
                }
                sug.deinit();

                name_entry.draw();
                name_entry.deinit();
            }

            // Player country input
            const country_input = widgets.textEntry(
                @src(),
                &player.country,
                applied_player.country.slice(),
                .{ .placeholder = "vn" },
                .{ .max_size_content = .width(30), .id_extra = id },
            );
            country_input.deinit();

            // Player score input
            widgets.textEntryNumber(@src(), &player.score, applied_player.score, id);
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
            const team_input = widgets.textEntry(
                @src(),
                &player.team,
                applied_player.team.slice(),
                .{},
                .{ .expand = .horizontal, .id_extra = id },
            );
            team_input.deinit();
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

fn apply() void {
    const io = threaded_io.io();
    applied_state_mutex.lock(io) catch @panic("failed to acquire lock on applied_state");
    defer applied_state_mutex.unlock(io);
    applied_state = state;
}
