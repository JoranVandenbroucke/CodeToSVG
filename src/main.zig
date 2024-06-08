const std = @import("std");
const clap = @import("clap");
const yaml = @import("yaml");
const lexer = @import("lexer.zig");

pub const Formatting = struct { button_margin_percent: f32, button_padding_percent: f32, code_margin_percent: f32, code_padding_percent: f32, button_radius: u8, font_size: u8, background_color: []const u8, close_color: []const u8, minimize_color: []const u8, maximize_color: []const u8, line_number_color: []const u8, fallback_color: []const u8, token_groups: []const struct {
    tokens: []const []const u8,
    color: []const u8,
} };

fn countDigits(number: usize) usize {
    if (number == 0) {
        return 1;
    }
    var count: usize = 0;
    var n = number;

    while (n != 0) {
        n /= 10;
        count += 1;
    }

    return count; // Account for the number 0 having 1 digit
}

fn changeExtension(file: []const u8, newExtention: []const u8) ![]u8 {
    const dirname = std.fs.path.dirname(file);
    const basename = std.fs.path.basename(file);
    const stem = std.fs.path.stem(basename);

    var buffer = try std.heap.page_allocator.alloc(u8, dirname.?.len + stem.len + newExtention.len + 1); // +1 for the slash
    std.mem.copyForwards(u8, buffer, dirname.?);
    buffer[dirname.?.len] = '/';
    std.mem.copyForwards(u8, buffer[dirname.?.len + 1 ..], stem);
    std.mem.copyForwards(u8, buffer[dirname.?.len + stem.len + 1 ..], newExtention);

    return buffer;
}

fn loadYaml(filePath: []const u8) !Formatting {
    const file = try std.fs.cwd().openFile(filePath, .{});
    defer file.close();

    const source = try file.readToEndAlloc(std.heap.page_allocator, std.math.maxInt(u32));

    var parsed = try yaml.Yaml.load(std.heap.page_allocator, source);
    return try parsed.parse(Formatting);
}

fn getColorFromTokeType(formatting: Formatting, kind: lexer.Kind) []const u8 {
    const typeName = @tagName(kind);
    for (formatting.token_groups) |group| {
        for (group.tokens) |token| {
            if (std.mem.count(u8, typeName, token) > 0) {
                return group.color;
            }
        }
    }
    return formatting.fallback_color;
}
fn getCorrectSvgLexeme(lexeme: []const u8) []const u8 {
    if (lexeme.len > 1)
        return lexeme;
    return switch (lexeme[0]) {
        '<' => "&lt;",
        '>' => "&gt;",
        '&' => "&amp;",
        '"' => "&quot;",
        '\'' => "&apos;",
        else => lexeme,
    };
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-v, --version  Output version information and exit.
        \\-f, --file <FILE> The Input Code File.
        \\-o, --output <SVG> The Output SVG Name.
        \\-s, --style <YML> Color Theme to use.
    );
    const parsers = comptime .{ .FILE = clap.parsers.string, .SVG = clap.parsers.string, .YML = clap.parsers.string };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    };

    var inputFileName: []const u8 = "";
    var outputFileName: []const u8 = "";
    var styleFile: []const u8 = "";

    defer res.deinit();

    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }
    if (res.args.version != 0) {
        std.debug.print("Version 1.0.0\n", .{}); // todo make it print without using debug.print
    }
    if (res.args.file) |f| {
        inputFileName = f;
        outputFileName = try changeExtension(inputFileName, ".svg");
    }
    if (res.args.output) |o| {
        outputFileName = try changeExtension(o, ".svg");
    }
    if (res.args.style) |s| {
        styleFile = try changeExtension(s, ".yaml");
    }
    if (std.mem.eql(u8, inputFileName, "")) {
        return;
    }

    var inputFile = try std.fs.cwd().openFile(inputFileName, .{});
    defer inputFile.close();

    var buffer: [4096]u8 = undefined;
    var bytesRead = try inputFile.read(buffer[0..]);

    // Process the complete tokens with the lexer
    var max_line_width: u32 = 0;
    var line_count: u16 = 1;
    var lastChar: u16 = 1;
    var tokenList = std.ArrayList(lexer.Token).init(std.heap.page_allocator);
    defer tokenList.deinit();

    while (bytesRead > 0) {
        var end = bytesRead;
        if (bytesRead == 4096) {
            while (end > 1 and buffer[end - 1] != '\n' and buffer[end - 1] != '\r' and buffer[end - 1] != 0) {
                end -= 1;
            }
        }

        var lex = lexer.Lexer{ .code = buffer[0..end], .cursor = 0, .line = line_count, .column = lastChar };
        while (true) {
            const token = lex.next();
            if (token.is_one_of(&[_]lexer.Kind{ lexer.Kind.End, lexer.Kind.Unexpected })) {
                break;
            }

            const lexemeSize: u32 = @intCast(token.lexeme.len);
            if (max_line_width < token.column + lexemeSize) {
                max_line_width = token.column + lexemeSize;
            }
            line_count = token.line;
            lastChar = token.column;

            try tokenList.append(token);
        }

        const remaining = bytesRead - end;
        if (remaining > 0) {
            std.mem.copyForwards(u8, buffer[0..remaining], buffer[end..bytesRead]);
        }

        // Read the next chunk into the buffer, after the remaining bytes
        bytesRead = remaining + try inputFile.read(buffer[remaining..]);
    }

    const style = try loadYaml(styleFile);

    const max_line_width_float: f32 = @floatFromInt(max_line_width);
    const line_count_float: f16 = @floatFromInt(line_count);
    const font_size_float: f16 = @floatFromInt(style.font_size);
    const circle_radius: f16 = @floatFromInt(style.button_radius);
    const circle_diameter: f16 = circle_radius * 2.0;

    // Approximating character width and line height based on font size
    const char_width: f16 = font_size_float / 2.0; // Approximation
    const line_height: f16 = font_size_float * 1.5; // Approximation

    const line_count_width: f16 = @floatFromInt(countDigits(line_count));

    const circle_margine: f32 = style.button_margin_percent * circle_diameter;
    const circle_padding: f32 = style.button_padding_percent * circle_diameter;
    const line_count_margine: f32 = style.code_margin_percent * 2 * line_count_width;
    const line_count_padding: f32 = style.code_padding_percent * 2 * line_count_width;
    const line_code_padding: f32 = style.code_padding_percent * 2 * max_line_width_float;

    const first_column_x: f32 = circle_margine + circle_padding;
    const circle_y: f32 = circle_margine + circle_padding + circle_padding + circle_radius;
    const circle_red_x: f32 = first_column_x + circle_radius;
    const circle_orange_x: f32 = circle_red_x + circle_diameter + circle_padding * 2;
    const circle_green_x: f32 = circle_orange_x + circle_diameter + circle_padding * 2;

    const window_width = line_count_margine * 2 + line_count_padding * 3 + line_code_padding + (line_count_margine + max_line_width_float) * char_width;
    const window_height = circle_margine * 2 + circle_padding * 2 + circle_diameter + line_count_margine * 2 + line_count_padding * 2 + line_count_float * line_height;

    var outputFile = try std.fs.cwd().createFile(outputFileName, .{});
    defer outputFile.close();
    const svgHeader = try std.fmt.allocPrint(std.heap.page_allocator,
        \\<svg width="{d}" height="{d}" xmlns="http://www.w3.org/2000/svg">
        \\    <rect x="0" y="0" width="{d}" height="{d}" rx="20" fill="{s}" />
        \\    <circle cx="{d}" cy="{d}" r="{d}" fill="{s}" />
        \\    <!-- Orange Button -->
        \\    <circle cx="{d}" cy="{d}" r="{d}" fill="{s}" />
        \\    <!-- Green Button -->
        \\    <circle cx="{d}" cy="{d}" r="{d}" fill="{s}" />
    , .{ window_width, window_height, window_width, window_height, style.background_color, circle_red_x, circle_y, circle_radius, style.close_color, circle_orange_x, circle_y, circle_radius, style.minimize_color, circle_green_x, circle_y, circle_radius, style.maximize_color });
    defer std.heap.page_allocator.free(svgHeader);
    try outputFile.writer().print("{s}\n", .{svgHeader});

    const text_start_y: f32 = circle_y + circle_radius + circle_padding + circle_margine + line_count_margine + line_count_padding;
    const text_line_nr_x: f32 = first_column_x + circle_radius + line_count_margine + line_count_padding;
    for (0..line_count) |i| {
        const idx_float: f32 = @floatFromInt(i);
        const y_position: u32 = @intFromFloat(text_start_y + idx_float * line_height);
        const lineNr = try std.fmt.allocPrint(std.heap.page_allocator,
            \\    <text text-anchor="end" fill="{s}" x="{d}" y="{d}" font-size="{d}">{d}.</text>
        , .{ style.line_number_color, text_line_nr_x, y_position, style.font_size, i + 1 });
        defer std.heap.page_allocator.free(lineNr);

        try outputFile.writer().print("{s}\n", .{lineNr});
    }

    const text_code_x: f32 = text_line_nr_x + line_count_padding * 2;
    var startText = try std.fmt.allocPrint(std.heap.page_allocator,
        \\    <text fill="{s}" x="{d}" y="{d}" font-size="{d}">
    , .{ style.line_number_color, text_code_x, text_start_y, style.font_size });
    try outputFile.writer().print("{s}", .{startText});

    var currentLine: u16 = 1;
    var previousCharEnd: u32 = 0;
    for (tokenList.items) |token| {
        if (currentLine != token.line) {
            const column: f16 = @floatFromInt(token.column - 1);
            const lineNr: f16 = @floatFromInt(token.line - 1);
            const x_position: f32 = text_code_x + column * char_width;
            const y_position: f32 = text_start_y + line_height * lineNr;

            startText = try std.fmt.allocPrint(std.heap.page_allocator,
                \\    </text>
                \\    <text fill="{s}" x="{d}" y="{d}" font-size="{d}">
            , .{ style.fallback_color, x_position, y_position, style.font_size });
            try outputFile.writer().print("{s}", .{startText});

            currentLine = token.line;
        }
        const color = getColorFromTokeType(style, token.kind);
        const lexeme = getCorrectSvgLexeme(token.lexeme);

        if (token.column < previousCharEnd or token.column - previousCharEnd == 0) {
            const lineNr = try std.fmt.allocPrint(std.heap.page_allocator,
                \\<tspan fill="{s}">{s}</tspan>
            , .{ color, lexeme });
            defer std.heap.page_allocator.free(lineNr);
            try outputFile.writer().print("{s}", .{lineNr});
        } else {
            const lineNr = try std.fmt.allocPrint(std.heap.page_allocator,
                \\<tspan fill="{s}"> {s}</tspan>
            , .{ color, lexeme });
            defer std.heap.page_allocator.free(lineNr);
            try outputFile.writer().print("{s}", .{lineNr});
        }
        const lexemeSize: u32 = @intCast(token.lexeme.len);
        previousCharEnd = token.column + lexemeSize;
    }
    _ = try outputFile.write("\n</text>\n</svg>");
}
