const std = @import("std");

const KeywordsCXX = [_][]const u8{ "alignas", "alignof", "and", "and_eq", "asm", "atomic_cancel", "atomic_commit", "atomic_noexcept", "auto", "bitand", "bitor", "bool", "break", "case", "catch", "char", "char8_t", "char16_t", "char32_t", "class", "compl", "concept", "const", "consteval", "constexpr", "constinit", "const_cast", "continue", "co_await", "co_return", "co_yield", "decltype", "default", "delete", "do", "double", "dynamic_cast", "else", "enum", "explicit", "export", "extern", "false", "float", "for", "friend", "goto", "if", "inline", "int", "long", "mutable", "namespace", "new", "noexcept", "not", "not_eq", "nullptr", "operator", "or", "or_eq", "private", "protected", "public", "reflexpr", "register", "reinterpret_cast", "requires", "return", "short", "signed", "sizeof (1)", "static", "static_assert", "static_cast", "struct", "switch", "synchronized", "template", "this", "thread_local", "throw", "true", "try", "typedef", "typeid", "typename", "union", "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while", "xor", "xor_eq" };

pub const Kind = enum {
    Number,
    Identifier,
    Keyword,
    LeftParen,
    RightParen,
    LeftSquare,
    RightSquare,
    LeftCurly,
    RightCurly,
    LessThan,
    GreaterThan,
    Equal,
    Plus,
    Minus,
    Asterisk,
    Slash,
    Hash,
    Dot,
    Comma,
    Colon,
    Semicolon,
    SingleQuote,
    DoubleQuote,
    Comment,
    Pipe,
    Ampersant,
    End,
    Unexpected,
};

pub const Token = struct {
    kind: Kind,
    lexeme: []const u8,
    line: u16,
    char: u16,

    pub fn is(self: *const Token, ki: Kind) bool {
        return self.kind == ki;
    }

    pub fn is_not(self: *const Token, ki: Kind) bool {
        return !self.is(ki);
    }

    pub fn is_one_of(self: *const Token, ks: []const Kind) bool {
        for (ks) |k| {
            if (self.is(k)) return true;
        }
        return false;
    }
};

pub const Lexer = struct {
    code: []const u8,
    cursor: u32,
    line: u16,
    char: u16,

    fn is_space(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }

    fn is_identifier_char(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_';
    }

    fn is_numeric(c: u8) bool {
        return std.ascii.isDigit(c);
    }

    fn peek(self: *const Lexer) u8 {
        return self.code[self.cursor];
    }

    fn get(self: *Lexer) u8 {
        const result = self.peek();
        self.cursor += 1;
        self.char += 1;
        return result;
    }

    fn slash_or_comment(self: *Lexer) Token {
        var start = self.cursor;
        _ = self.get();
        if (self.peek() == '/') {
            _ = self.get();
            start = self.cursor;
            while (self.peek() != 0) {
                if (self.get() == '\n') {
                    const size: u16 = @intCast(self.cursor - start);
                    const token = Token{ .kind = Kind.Comment, .lexeme = self.code[start - 2 .. self.cursor - 1], .line = self.line, .char = self.char - size - 2 };
                    self.line += 1;
                    self.char = 0;
                    return token;
                }
            }
            const size: u16 = @intCast(self.cursor - start);
            return Token{ .kind = Kind.Unexpected, .lexeme = self.code[self.cursor .. self.cursor + 1], .line = self.line, .char = self.char - size };
        }
        const size: u16 = @intCast(self.cursor - start);
        return Token{ .kind = Kind.Slash, .lexeme = self.code[start..self.cursor], .line = self.line, .char = self.char - size };
    }

    fn identifier(self: *Lexer) Token {
        const start = self.cursor;
        _ = self.get();
        while (is_identifier_char(self.peek())) _ = self.get();
        const size: u16 = @intCast(self.cursor - start);
        const lexeme = self.code[start..self.cursor];
        for (KeywordsCXX) |keyword| {
            if (std.mem.eql(u8, keyword, lexeme))
                return Token{ .kind = Kind.Keyword, .lexeme = lexeme, .line = self.line, .char = self.char - size };
        }
        return Token{ .kind = Kind.Identifier, .lexeme = lexeme, .line = self.line, .char = self.char - size };
    }

    fn number(self: *Lexer) Token {
        const start = self.cursor;
        _ = self.get();
        while (is_numeric(self.peek())) _ = self.get();

        const size: u16 = @intCast(self.cursor - start);
        return Token{ .kind = Kind.Number, .lexeme = self.code[start..self.cursor], .line = self.line, .char = self.char - size };
    }

    fn atom(self: *Lexer, kind: Kind) Token {
        self.cursor += 1;
        self.char += 1;
        return Token{ .kind = kind, .lexeme = self.code[self.cursor - 1 .. self.cursor], .line = self.line, .char = self.char - 1 };
    }

    pub fn next(self: *Lexer) Token {
        if (self.cursor == self.code.len)
            return Token{ .kind = Kind.End, .lexeme = &[_]u8{0}, .line = self.line, .char = 0 };

        while (is_space(self.peek())) {
            _ = self.get();
            if (self.cursor == self.code.len)
                return Token{ .kind = Kind.End, .lexeme = &[_]u8{0}, .line = self.line, .char = 0 };
            if (self.peek() == '\n') {
                self.line += 1;
                self.char = 0;
            }
        }

        return switch (self.peek()) {
            0 => Token{ .kind = Kind.End, .lexeme = &[_]u8{0}, .line = self.line, .char = self.char },
            'a'...'z', 'A'...'Z' => self.identifier(),
            '0'...'9' => self.number(),
            '/' => self.slash_or_comment(),
            '(' => self.atom(Kind.LeftParen),
            ')' => self.atom(Kind.RightParen),
            '[' => self.atom(Kind.LeftSquare),
            ']' => self.atom(Kind.RightSquare),
            '{' => self.atom(Kind.LeftCurly),
            '}' => self.atom(Kind.RightCurly),
            '<' => self.atom(Kind.LessThan),
            '>' => self.atom(Kind.GreaterThan),
            '=' => self.atom(Kind.Equal),
            '+' => self.atom(Kind.Plus),
            '-' => self.atom(Kind.Minus),
            '*' => self.atom(Kind.Asterisk),
            '#' => self.atom(Kind.Hash),
            '.' => self.atom(Kind.Dot),
            ',' => self.atom(Kind.Comma),
            ':' => self.atom(Kind.Colon),
            ';' => self.atom(Kind.Semicolon),
            '\'' => self.atom(Kind.SingleQuote),
            '"' => self.atom(Kind.DoubleQuote),
            '|' => self.atom(Kind.Pipe),
            '&' => self.atom(Kind.Ampersant),
            else => self.atom(Kind.Unexpected),
        };
    }
};
