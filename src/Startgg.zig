const std = @import("std");
const Io = std.Io;
const State = @import("./State.zig");
const EntryString = State.EntryString;
const MAX_TEXT_LENGTH = State.MAX_TEXT_LENGTH;
const log = std.log.scoped(.Startgg);
const PlayerLookup = @import("./PlayerLookup.zig");

pub const INPUTS_FILE = "startgg-inputs.txt";
const DELIMITER = ':';
const API_URL = "https://api.start.gg/gql/alpha";
//const API_URL = "http://localhost:8080"; // python debugsrv.py

const Self = @This();

tournament_slug: EntryString = .{},
token: EntryString = .{},

pub fn loadFile(io: Io) Self {
    var buf: [4096]u8 = undefined;
    const slice = Io.Dir.cwd().readFile(io, INPUTS_FILE, &buf) catch return .{};
    var parts = std.mem.splitScalar(u8, slice, DELIMITER);

    const tournament_slug = parts.next();
    const token = parts.next();

    if (tournament_slug == null or token == null) {
        log.err(
            \\{s} is malformed. Must be "tournament-slug{c}token".
        ,
            .{ INPUTS_FILE, DELIMITER },
        );
        return .{};
    }

    return .{
        .token = .init(token.?),
        .tournament_slug = .init(tournament_slug.?),
    };
}

pub fn writeFile(self: *Self, io: Io) !void {
    const file = try Io.Dir.cwd().createFile(io, INPUTS_FILE, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var writer = file.writer(io, &buf);

    try writer.interface.writeAll(self.tournament_slug.slice());
    try writer.interface.writeByte(DELIMITER);
    try writer.interface.writeAll(self.token.slice());

    try writer.flush();
}

pub fn importTournament(
    self: *Self,
    gpa: std.mem.Allocator,
    io: Io,
    player_lookup: *PlayerLookup,
) !void {
    var query_buf: [1024]u8 = undefined;
    var query_writer = Io.Writer.fixed(&query_buf);
    try query_writer.writeAll(
        \\{
        \\  tournament(slug: "
    );
    try query_writer.writeAll(self.tournament_slug.slice());
    try query_writer.writeAll(
        \\") {
        \\    participants(query: {page:
    );
    try query_writer.print(" {d}", .{1}); // TODO do we need to paginate?
    try query_writer.writeAll(
        \\, perPage: 500}) {
        \\      nodes {
        \\        entrants {
        \\          event {
        \\            slug
        \\            name
        \\          }
        \\          team {
        \\            name
        \\          }
        \\        }
        \\        gamerTag
        \\        prefix
        \\        user {
        \\          location {
        \\            country
        \\          }
        \\        }
        \\      }
        \\    }
        \\  }
        \\}
    );

    const request_body = RequestBody{
        .query = query_writer.buffered(),
    };

    var payload_buf: [2048]u8 = undefined;
    var payload_writer = Io.Writer.fixed(&payload_buf);
    var payload_json = std.json.Stringify{ .writer = &payload_writer };
    try payload_json.write(request_body);

    // For some reason std.http.Client.fetch() seems to drop the last 2
    // bytes from the request body, so here I'm appending 2 sacrificial bytes.
    // TODO: See if it's fixed in 0.17, otherwise investigate further.
    // Btw, when start.gg API responds with "POST body not found", it actually
    // means our request body is not valid JSON.
    try payload_writer.writeAll("\n\n");

    const payload = payload_writer.buffered();

    var token_header_buf: [256]u8 = undefined;
    const token_header = try std.fmt.bufPrint(
        &token_header_buf,
        "Bearer {s}",
        .{self.token.slice()},
    );

    var resp_writer = try Io.Writer.Allocating.initCapacity(gpa, 1024 * 8);
    defer resp_writer.deinit();

    var http_client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer http_client.deinit();

    log.info("sending start.gg request...", .{});
    const start = Io.Clock.now(.awake, io);

    const result = try http_client.fetch(.{
        .location = .{ .url = API_URL },
        // Setting .headers here seems to disable the Content-Length
        // header too. No idea why. For now let's just not touch it.
        // TODO: revisit in 0.17.
        // .headers = .{
        //     .user_agent = .{ .override = "ZORTS/0.5" },
        //     .content_type = .{ .override = "application/json" },
        //     .authorization = .{ .override = token_header },
        // },
        .extra_headers = &.{
            .{ .name = "Authorization", .value = token_header },
        },
        .method = .POST,
        .payload = payload,
        .response_writer = &resp_writer.writer,
    });

    const end = std.Io.Clock.now(.awake, io);
    const duration = start.durationTo(end);

    const response = resp_writer.writer.buffered();

    log.info("{s}", .{response});

    log.info(
        "got status: {d}, body: {d} bytes, took {d}s",
        .{ result.status, response.len, duration.toSeconds() },
    );

    var parsed = try std.json.parseFromSlice(
        ResponseBody,
        gpa,
        response,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    var buf: [4096]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    var stringify = std.json.Stringify{
        .writer = &writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(parsed.value);
    log.info("resp body:\n{s}", .{writer.buffered()});

    player_lookup.players.clearRetainingCapacity();
    for (parsed.value.data.tournament.participants.nodes) |node| {
        const name = node.gamerTag;
        const prefix = node.prefix;
        const country_name = node.user.location.country;

        // TODO how should I handle multiple teams?
        const team = if (node.entrants[0].team) |team| team.name else "";

        const country_code =
            if (country_name_to_code.get(country_name)) |code|
                code
            else
                "";

        var name_buf: [MAX_TEXT_LENGTH]u8 = undefined;
        const player_name =
            if (prefix.len > 0)
                try std.fmt.bufPrint(&name_buf, "{s} {s}", .{ prefix, name })
            else
                name;

        var player_bio = PlayerLookup.PlayerBio{
            .country = .init(country_code),
            .name = .init(player_name),
            .team = .init(team),
        };
        player_bio.normalized_name = player_bio.name.normalized();
        try player_lookup.players.append(gpa, player_bio);
    }
}

const RequestBody = struct {
    query: []const u8,
};

const ResponseBody = struct {
    data: struct {
        tournament: struct {
            participants: struct {
                nodes: []struct {
                    entrants: []struct {
                        team: ?struct {
                            name: []const u8,
                        },
                    },
                    gamerTag: []const u8,
                    prefix: []const u8,
                    user: struct {
                        location: struct {
                            country: []const u8,
                        },
                    },
                },
            },
        },
    },
};

// Startgg only shows (non-standard) country names (ongoing problem for years,
// probably will never be fixed), so we need this mapping to convert these
// names to alpha-2 codes.
// From https://gist.github.com/morleym/a39c43f6544a350c109c5f7b0b055155
pub const country_name_to_code = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Bangladesh", "bd" },
    .{ "Belgium", "be" },
    .{ "Burkina Faso", "bf" },
    .{ "Bulgaria", "bg" },
    .{ "Bosnia and Herzegovina", "ba" },
    .{ "Barbados", "bb" },
    .{ "Wallis and Futuna", "wf" },
    .{ "Saint Barthelemy", "bl" },
    .{ "Bermuda", "bm" },
    .{ "Brunei", "bn" },
    .{ "Bolivia", "bo" },
    .{ "Bahrain", "bh" },
    .{ "Burundi", "bi" },
    .{ "Benin", "bj" },
    .{ "Bhutan", "bt" },
    .{ "Jamaica", "jm" },
    .{ "Bouvet Island", "bv" },
    .{ "Botswana", "bw" },
    .{ "Samoa", "ws" },
    .{ "Bonaire, Saint Eustatius and Saba ", "bq" },
    .{ "Brazil", "br" },
    .{ "Bahamas", "bs" },
    .{ "Jersey", "je" },
    .{ "Belarus", "by" },
    .{ "Belize", "bz" },
    .{ "Russia", "ru" },
    .{ "Rwanda", "rw" },
    .{ "Serbia", "rs" },
    .{ "East Timor", "tl" },
    .{ "Reunion", "re" },
    .{ "Turkmenistan", "tm" },
    .{ "Tajikistan", "tj" },
    .{ "Romania", "ro" },
    .{ "Tokelau", "tk" },
    .{ "Guinea-Bissau", "gw" },
    .{ "Guam", "gu" },
    .{ "Guatemala", "gt" },
    .{ "South Georgia and the South Sandwich Islands", "gs" },
    .{ "Greece", "gr" },
    .{ "Equatorial Guinea", "gq" },
    .{ "Guadeloupe", "gp" },
    .{ "Japan", "jp" },
    .{ "Guyana", "gy" },
    .{ "Guernsey", "gg" },
    .{ "French Guiana", "gf" },
    .{ "Georgia", "ge" },
    .{ "Grenada", "gd" },
    .{ "United Kingdom", "gb" },
    .{ "Gabon", "ga" },
    .{ "El Salvador", "sv" },
    .{ "Guinea", "gn" },
    .{ "Gambia", "gm" },
    .{ "Greenland", "gl" },
    .{ "Gibraltar", "gi" },
    .{ "Ghana", "gh" },
    .{ "Oman", "om" },
    .{ "Tunisia", "tn" },
    .{ "Jordan", "jo" },
    .{ "Croatia", "hr" },
    .{ "Haiti", "ht" },
    .{ "Hungary", "hu" },
    .{ "Hong Kong", "hk" },
    .{ "Honduras", "hn" },
    .{ "Heard Island and McDonald Islands", "hm" },
    .{ "Venezuela", "ve" },
    .{ "Puerto Rico", "pr" },
    .{ "Palestinian Territory", "ps" },
    .{ "Palau", "pw" },
    .{ "Portugal", "pt" },
    .{ "Svalbard and Jan Mayen", "sj" },
    .{ "Paraguay", "py" },
    .{ "Iraq", "iq" },
    .{ "Panama", "pa" },
    .{ "French Polynesia", "pf" },
    .{ "Papua New Guinea", "pg" },
    .{ "Peru", "pe" },
    .{ "Pakistan", "pk" },
    .{ "Philippines", "ph" },
    .{ "Pitcairn", "pn" },
    .{ "Poland", "pl" },
    .{ "Saint Pierre and Miquelon", "pm" },
    .{ "Zambia", "zm" },
    .{ "Western Sahara", "eh" },
    .{ "Estonia", "ee" },
    .{ "Egypt", "eg" },
    .{ "South Africa", "za" },
    .{ "Ecuador", "ec" },
    .{ "Italy", "it" },
    .{ "Vietnam", "vn" },
    .{ "Solomon Islands", "sb" },
    .{ "Ethiopia", "et" },
    .{ "Somalia", "so" },
    .{ "Zimbabwe", "zw" },
    .{ "Saudi Arabia", "sa" },
    .{ "Spain", "es" },
    .{ "Eritrea", "er" },
    .{ "Montenegro", "me" },
    .{ "Moldova", "md" },
    .{ "Madagascar", "mg" },
    .{ "Saint Martin", "mf" },
    .{ "Morocco", "ma" },
    .{ "Monaco", "mc" },
    .{ "Uzbekistan", "uz" },
    .{ "Myanmar", "mm" },
    .{ "Mali", "ml" },
    .{ "Macao", "mo" },
    .{ "Mongolia", "mn" },
    .{ "Marshall Islands", "mh" },
    .{ "Macedonia", "mk" },
    .{ "Mauritius", "mu" },
    .{ "Malta", "mt" },
    .{ "Malawi", "mw" },
    .{ "Maldives", "mv" },
    .{ "Martinique", "mq" },
    .{ "Northern Mariana Islands", "mp" },
    .{ "Montserrat", "ms" },
    .{ "Mauritania", "mr" },
    .{ "Isle of Man", "im" },
    .{ "Uganda", "ug" },
    .{ "Tanzania", "tz" },
    .{ "Malaysia", "my" },
    .{ "Mexico", "mx" },
    .{ "Israel", "il" },
    .{ "France", "fr" },
    .{ "British Indian Ocean Territory", "io" },
    .{ "Saint Helena", "sh" },
    .{ "Finland", "fi" },
    .{ "Fiji", "fj" },
    .{ "Falkland Islands", "fk" },
    .{ "Micronesia", "fm" },
    .{ "Faroe Islands", "fo" },
    .{ "Nicaragua", "ni" },
    .{ "Netherlands", "nl" },
    .{ "Norway", "no" },
    .{ "Namibia", "na" },
    .{ "Vanuatu", "vu" },
    .{ "New Caledonia", "nc" },
    .{ "Niger", "ne" },
    .{ "Norfolk Island", "nf" },
    .{ "Nigeria", "ng" },
    .{ "New Zealand", "nz" },
    .{ "Nepal", "np" },
    .{ "Nauru", "nr" },
    .{ "Niue", "nu" },
    .{ "Cook Islands", "ck" },
    .{ "Kosovo", "xk" },
    .{ "Ivory Coast", "ci" },
    .{ "Switzerland", "ch" },
    .{ "Colombia", "co" },
    .{ "China", "cn" },
    .{ "Cameroon", "cm" },
    .{ "Chile", "cl" },
    .{ "Cocos Islands", "cc" },
    .{ "Canada", "ca" },
    .{ "CA", "ca" },
    .{ "Republic of the Congo", "cg" },
    .{ "Central African Republic", "cf" },
    .{ "Democratic Republic of the Congo", "cd" },
    .{ "Czech Republic", "cz" },
    .{ "Cyprus", "cy" },
    .{ "Christmas Island", "cx" },
    .{ "Costa Rica", "cr" },
    .{ "Curacao", "cw" },
    .{ "Cape Verde", "cv" },
    .{ "Cuba", "cu" },
    .{ "Swaziland", "sz" },
    .{ "Syria", "sy" },
    .{ "Sint Maarten", "sx" },
    .{ "Kyrgyzstan", "kg" },
    .{ "Kenya", "ke" },
    .{ "South Sudan", "ss" },
    .{ "Suriname", "sr" },
    .{ "Kiribati", "ki" },
    .{ "Cambodia", "kh" },
    .{ "Saint Kitts and Nevis", "kn" },
    .{ "Comoros", "km" },
    .{ "Sao Tome and Principe", "st" },
    .{ "Slovakia", "sk" },
    .{ "South Korea", "kr" },
    .{ "Slovenia", "si" },
    .{ "North Korea", "kp" },
    .{ "Kuwait", "kw" },
    .{ "Senegal", "sn" },
    .{ "San Marino", "sm" },
    .{ "Sierra Leone", "sl" },
    .{ "Seychelles", "sc" },
    .{ "Kazakhstan", "kz" },
    .{ "Cayman Islands", "ky" },
    .{ "Singapore", "sg" },
    .{ "Sweden", "se" },
    .{ "Sudan", "sd" },
    .{ "Dominican Republic", "do" },
    .{ "Dominica", "dm" },
    .{ "Djibouti", "dj" },
    .{ "Denmark", "dk" },
    .{ "British Virgin Islands", "vg" },
    .{ "Germany", "de" },
    .{ "Yemen", "ye" },
    .{ "Algeria", "dz" },
    .{ "United States", "us" },
    .{ "US", "us" },
    .{ "Uruguay", "uy" },
    .{ "Mayotte", "yt" },
    .{ "United States Minor Outlying Islands", "um" },
    .{ "Lebanon", "lb" },
    .{ "Saint Lucia", "lc" },
    .{ "Laos", "la" },
    .{ "Tuvalu", "tv" },
    .{ "Taiwan", "tw" },
    .{ "Trinidad and Tobago", "tt" },
    .{ "Turkey", "tr" },
    .{ "Sri Lanka", "lk" },
    .{ "Liechtenstein", "li" },
    .{ "Latvia", "lv" },
    .{ "Tonga", "to" },
    .{ "Lithuania", "lt" },
    .{ "Luxembourg", "lu" },
    .{ "Liberia", "lr" },
    .{ "Lesotho", "ls" },
    .{ "Thailand", "th" },
    .{ "French Southern Territories", "tf" },
    .{ "Togo", "tg" },
    .{ "Chad", "td" },
    .{ "Turks and Caicos Islands", "tc" },
    .{ "Libya", "ly" },
    .{ "Vatican", "va" },
    .{ "Saint Vincent and the Grenadines", "vc" },
    .{ "United Arab Emirates", "ae" },
    .{ "Andorra", "ad" },
    .{ "Antigua and Barbuda", "ag" },
    .{ "Afghanistan", "af" },
    .{ "Anguilla", "ai" },
    .{ "U.S. Virgin Islands", "vi" },
    .{ "Iceland", "is" },
    .{ "Iran", "ir" },
    .{ "Armenia", "am" },
    .{ "Albania", "al" },
    .{ "Angola", "ao" },
    .{ "Antarctica", "aq" },
    .{ "American Samoa", "as" },
    .{ "Argentina", "ar" },
    .{ "Australia", "au" },
    .{ "Austria", "at" },
    .{ "Aruba", "aw" },
    .{ "India", "in" },
    .{ "Aland Islands", "ax" },
    .{ "Azerbaijan", "az" },
    .{ "Ireland", "ie" },
    .{ "Indonesia", "id" },
    .{ "Ukraine", "ua" },
    .{ "Qatar", "qa" },
    .{ "Mozambique", "mz" },
    .{ "Wales", "gb-wls" },
    .{ "Scotland", "gb-sct" },
});
