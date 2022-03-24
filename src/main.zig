const std = @import("std");
const print = @import("std").debug.print;
const File = std.fs.File;
const ArrayList = std.ArrayList;

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}

pub fn readInput(allocator: std.mem.Allocator, file: *File) ![:0]u8 {
    const source_code = file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, // size_hint
        @alignOf(u16), 0) catch |err| switch (err) {
        error.ConnectionResetByPeer => unreachable,
        error.ConnectionTimedOut => unreachable,
        error.NotOpenForReading => unreachable,
        else => |e| return e,
    };
    errdefer allocator.free(source_code);
    return source_code;
}

const Token = struct {
    id: Id,
    start: usize,
    end: usize,

    pub const Id = union(enum) {
        None,
        LParen,
        RParen,
        Identifier,
        Keyword,
        UnsignedLiteral,
        SignedLiteral,
        HexadecimalLiteral,
        SignedHexadecimalLiteral,
        FloatingPointLiteral,
        StringLiteral,
        Comment,
    };

    pub fn toStr(self: Token, buffer: [:0]u8) []const u8 {
        return switch (self.id) {
            .None => "",
            .LParen => "(",
            .RParen => ")",
            .Comment => "",
            // FIXME: Add surrounding ". We will need to allocate memory and this will complicate many things.
            // var string = try allocator.alloc(u8, self.end - self.start + 2);
            // string[0] = '"';
            // std.mem.copy(u8, string[1..], buffer[self.start .. self.end + 1]);
            // string[self.end - self.start + 1] = '"';
            .StringLiteral => buffer[self.start .. self.end + 1],
            .UnsignedLiteral, .SignedLiteral => buffer[self.start .. self.end + 1],
            else => buffer[self.start .. self.end + 1],
        };
    }
};

/// A tokenizer according to https://webassembly.github.io/spec/core/text/lexical.html
pub fn tokenize(allocator: std.mem.Allocator, buffer: [:0]u8) !ArrayList(Token) {
    const TokenizerState = enum {
        Root,
        Identifier,
        Keyword,
        StringLiteral,
        CharLiteral,
        SignedLiteral,
        UnsignedLiteral,
        SignedFloatLiteral,
        UnsignedFloatLiteral,
        SignedHexaFloatLiteral,
        UnsignedHexaFloatLiteral,
        HexadecimalLiteral,
        SignedHexadecimalLiteral,
        Comment,
        BlockComment,
    };

    var tokens = ArrayList(Token).init(allocator);
    var index: usize = 0;
    var state: TokenizerState = .Root;
    var start: usize = index;
    var end: usize = index;
    while (index < buffer.len) : (index += 1) {
        const c = buffer[index];
        print("index {} c {u} state {}\n", .{ index, c, state });
        switch (state) {
            .Root => switch (c) {
                '(' => {
                    if (index + 1 < buffer.len and buffer[index + 1] == ';') {
                        state = .BlockComment;
                    } else {
                        try tokens.append(Token{ .id = Token.Id.LParen, .start = index, .end = index });
                    }
                },
                ')' => try tokens.append(Token{ .id = Token.Id.RParen, .start = index, .end = index }),
                '$' => {
                    start = index;
                    state = .Identifier;
                },
                'a'...'z' => {
                    start = index;
                    state = .Keyword;
                },
                '0' => {
                    start = index;
                    state = .UnsignedLiteral;
                    // Look ahead
                    if (index + 1 < buffer.len and buffer[index + 1] == 'x') {
                        index += 1;
                        state = .HexadecimalLiteral;
                    }
                },
                '1'...'9' => {
                    start = index;
                    state = .UnsignedLiteral;
                },
                '+', '-' => {
                    start = index;
                    state = .SignedLiteral;
                    // Look ahead
                    if (index + 1 < buffer.len and buffer[index + 1] == '0') {
                        if (index + 2 < buffer.len and buffer[index + 2] == 'x') {
                            index += 2;
                            state = .SignedHexadecimalLiteral;
                        }
                    }
                },
                '"' => {
                    start = index;
                    state = .StringLiteral;
                },
                ';' => {
                    // Look ahead
                    if (index + 1 < buffer.len and buffer[index + 1] == ';') {
                        state = .Comment;
                    }
                },
                else => {},
            },
            .Identifier => switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '$', '_', '.', '+', '-', '*', '/', '\\', '^', '~', '=', '<', '>', '!', '?', '@', '#', '%', '&', '|', ':', '`' => end = index,
                else => {
                    index -= 1;
                    state = .Root;
                    try tokens.append(Token{ .id = Token.Id.Identifier, .start = start, .end = end });
                },
            },
            .Keyword => switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '$', '_', '.', '+', '-', '*', '/', '\\', '^', '~', '=', '<', '>', '!', '?', '@', '#', '%', '&', '|', ':', '`' => end = index,
                else => {
                    index -= 1;
                    state = .Root;
                    try tokens.append(Token{ .id = Token.Id.Keyword, .start = start, .end = end });
                },
            },
            .StringLiteral => switch (c) {
                '"' => {
                    state = .Root;
                    try tokens.append(Token{ .id = Token.Id.StringLiteral, .start = start + 1, .end = end });
                },
                else => end = index,
            },
            .UnsignedLiteral, .SignedLiteral => switch (c) {
                '0'...'9', '_' => end = index,
                '.' => state = if (state == .SignedLiteral) .SignedFloatLiteral else .UnsignedFloatLiteral,
                else => {
                    state = .Root;
                    const id = if (state == .SignedLiteral) Token.Id.SignedLiteral else Token.Id.UnsignedLiteral;
                    try tokens.append(Token{ .id = id, .start = start, .end = index - 1 });
                },
            },
            .HexadecimalLiteral, .SignedHexadecimalLiteral => switch (c) {
                '0'...'9', 'A'...'F' => end = index,
                '.' => state = if (state == .SignedHexadecimalLiteral) .SignedHexaFloatLiteral else .UnsignedHexaFloatLiteral,
                else => {
                    const id = if (state == .SignedHexadecimalLiteral)
                        Token.Id.SignedHexadecimalLiteral
                    else
                        Token.Id.HexadecimalLiteral;
                    try tokens.append(Token{ .id = id, .start = start, .end = end });
                },
            },
            .UnsignedFloatLiteral => {},
            .SignedFloatLiteral => {},
            .UnsignedHexaFloatLiteral => {},
            .SignedHexaFloatLiteral => {},
            .Comment => switch (c) {
                '\n' => state = .Root,
                else => {},
            },
            .BlockComment => switch (c) {
                ';' => {
                    if (index + 1 < buffer.len and buffer[index + 1] == ')') {
                        state = .Root;
                    }
                },
                else => {},
            },
            .CharLiteral => {},
        }
    }
    return tokens;
}

pub fn main() anyerror!void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    // var allocator = arena.allocator();
    var allocator = std.testing.allocator;
    const input = &std.io.getStdIn();

    const source_code: [:0]u8 = readInput(allocator, input) catch |err| {
        fatal("unable to read stdin: {s}", .{err});
    };
    defer allocator.free(source_code);

    const tokens = try tokenize(allocator, source_code);
    defer tokens.deinit();

    for (tokens.items) |token, index| {
        // print("{s}({}, {})", .{ Token.Id.symbol(token.id), token.start, token.end });
        print("{s}", .{token.toStr(source_code)});
        if (index != tokens.items.len - 1) {
            print(" ", .{});
        }
    }
    print("\n", .{});
}
