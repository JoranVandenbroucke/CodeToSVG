const std = @import("std");
const clap = @import("clap");
const yaml = @import("yaml");
const lexer = @import("lexer.zig");

pub const Formatting = struct { background_color: []const u8, close_color: []const u8, minimize_color: []const u8, maximize_color: []const u8, line_number_color: []const u8, fallback_color: []const u8, font_size: u32, padding: f32, token_groups: []const struct {
    tokens: []const []const u8,
    color: []const u8,
} };

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
    var width: u32 = 0;
    var lastLine: u16 = 1;
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

        var lex = lexer.Lexer{ .code = buffer[0..end], .cursor = 0, .line = lastLine, .char = lastChar };
        while (true) {
            const token = lex.next();
            if (token.is_one_of(&[_]lexer.Kind{ lexer.Kind.End, lexer.Kind.Unexpected })) {
                break;
            }

            const lexemeSize: u32 = @intCast(token.lexeme.len);
            if (width < token.char + lexemeSize) {
                width = token.char + lexemeSize;
            }
            lastLine = token.line;
            lastChar = token.char;

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

    var wordSize: f32 = @floatFromInt(lastLine);
    const fontSize: f32 = @floatFromInt(style.font_size);
    const height: u32 = @intFromFloat((50.0 + fontSize * wordSize) * (1.0 + style.padding + style.padding));
    wordSize = @floatFromInt(width);
    width = @intFromFloat((50.0 + fontSize * wordSize) * (1.0 + style.padding + style.padding));

    var outputFile = try std.fs.cwd().createFile(outputFileName, .{});
    defer outputFile.close();
    const svgHeader = try std.fmt.allocPrint(std.heap.page_allocator,
        \\<svg width="{d}" height="{d}" xmlns="http://www.w3.org/2000/svg">
        \\    <rect x="0" y="0" width="{d}" height="{d}" rx="20" fill="{s}" />
        \\    <circle cx="26" cy="26" r="6" fill="{s}" />
        \\    <!-- Orange Button -->
        \\    <circle cx="46" cy="26" r="6" fill="{s}" />
        \\    <!-- Green Button -->
        \\    <circle cx="66" cy="26" r="6" fill="{s}" />
    , .{ width, height, width, height, style.background_color, style.close_color, style.minimize_color, style.maximize_color });
    defer std.heap.page_allocator.free(svgHeader);

    try outputFile.writer().print("{s}\n", .{svgHeader});

    var charHeight: u32 = 64;
    for (1..lastLine + 1) |i| {
        const lineNr = try std.fmt.allocPrint(std.heap.page_allocator,
            \\    <text fill="{s}" x="26" y="{d}" font-size="{d}">{d}.</text>
        , .{ style.line_number_color, charHeight, style.font_size, i });
        defer std.heap.page_allocator.free(lineNr);

        try outputFile.writer().print("{s}\n", .{lineNr});
        charHeight += style.font_size;
    }
    charHeight = 64;

    var startText = try std.fmt.allocPrint(std.heap.page_allocator,
        \\    <text fill="{s}" x="52" y="{d}" font-size="{d}">
    , .{ style.line_number_color, charHeight, style.font_size });
    try outputFile.writer().print("{s}", .{startText});

    var currentLine: u16 = 1;
    var previousCharEnd: u32 = 0;
    for (tokenList.items) |token| {
        if (currentLine != token.line) {
            currentLine = token.line;

            startText = try std.fmt.allocPrint(std.heap.page_allocator,
                \\    </text>
                \\    <text fill="{s}" x="{d}" y="{d}" font-size="{d}">
            , .{ style.line_number_color, 52 + style.font_size * (token.char - 1), charHeight + style.font_size * (currentLine - 1), style.font_size });
            try outputFile.writer().print("{s}", .{startText});
        }
        const color = getColorFromTokeType(style, token.kind);
        const lexeme = getCorrectSvgLexeme(token.lexeme);

        if (token.char < previousCharEnd or token.char - previousCharEnd == 0) {
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
        previousCharEnd = token.char + lexemeSize;
    }
    _ = try outputFile.write("\n</text>\n</svg>");
}
