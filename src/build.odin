package lava

Compiler_State :: struct {
	file_names: [dynamic]string,
	file_data:  [dynamic]string,
	modules:    [dynamic]Package,
	ast:        [dynamic]Node,
	parsers:    [dynamic]Parser,
}
Package :: struct {
	name: string,
}
File :: struct {}
Pos :: struct {
	file:       string,
	pos:        int,
	line:       int,
	start_line: int,
	col:        int,
}

Node :: struct {
	pos: Pos,
}
TokenKind :: enum u32 {
	Invalid,
	EOF,
	Begin_Op,
	Plus,
	Minus,
	Mul,
	Div,
	End_Op,
	Begin_Literal,
	Ident,
	Int,
	Float,
	End_Literal,
	Begin_Keyword,
	Pkg,
	End_Keyword,
	COUNT,
}
tokens := [TokenKind.COUNT]string {
	TokenKind.Invalid       = "",
	TokenKind.EOF           = "",
	TokenKind.Begin_Op      = "",
	TokenKind.Plus          = "+",
	TokenKind.Minus         = "-",
	TokenKind.Mul           = "*",
	TokenKind.Div           = "/",
	TokenKind.End_Op        = "",
	TokenKind.Begin_Literal = "",
	TokenKind.Int           = "int",
	TokenKind.Float         = "float",
	TokenKind.End_Literal   = "",
	TokenKind.Begin_Keyword = "",
	TokenKind.Pkg           = "pkg",
	TokenKind.End_Keyword   = "",
}
Token :: struct {
	kind: TokenKind,
	lit:  string,
	pos:  Pos,
}
Tokenizer :: struct {
	path:       string,
	src:        string,
	rpos:       int,
	pos:        int,
	r:          rune,
	rprev:      rune,
	nlines:     int,
	start_line: int,
	nerrors:    int,
}


advance_rune :: proc(t: ^Tokenizer) {
	t.rprev = t.r
	if t.rpos >= len(t.src) {
		t.r = 0
		return
	}

	t.pos = t.rpos

	if t.r == '\n' {
		t.nlines += 1
		t.start_line = t.pos

	}

	w := 1
	r := rune(t.src[t.rpos])
	switch {
	case r == 0:
		panic("Null rune")
	case r >= utf8.RUNE_SELF:
		r, w = utf8.decode_rune_in_string(t.src[t.rpos:])
		if r == utf8.RUNE_ERROR && w == 1 {
			panic("illegal UTF-8 encoding")
		} else if r == utf8.RUNE_BOM && t.rpos > 0 {
			panic("illegal byte order mark")
		}
	}
	t.rpos += w
	t.r = r
	return

}
get_pos :: proc(t: ^Tokenizer) -> Pos {
	pos := Pos{}
	pos.file = t.path
	pos.line = t.nlines + 1

	pos.start_line = t.start_line
	pos.pos = t.pos
	pos.col = t.pos - t.start_line + 1
	return pos
}
peek_byte :: proc(t: ^Tokenizer, offset := 0) -> u8 {
	if t.rpos + offset < len(t.src) {
		return t.src[t.rpos + offset]
	}
	return 0
}

is_digit_no_val :: proc(r: rune) -> bool {
	switch r {
	case '0' ..= '9':
		return true
	case 'A' ..= 'F':
		return true
	case 'a' ..= 'f':
		return true
	}
	return false
}
is_digit_val :: proc(r: rune) -> (bool, int) {
	switch r {
	case '0' ..= '9':
		return true, int(r - '0')
	case 'A' ..= 'F':
		return true, int(r - 'A' + 10)
	case 'a' ..= 'f':
		return true, int(r - 'a' + 10)
	}
	return false, 16
}
scan_number :: proc(t: ^Tokenizer, start_point: bool = false) -> (TokenKind, string) {
	scan_digits :: proc(t: ^Tokenizer, base: int) {
		for {
			is_dig, val := is_digit_val(t.r)

			if (t.r == '_') {
				advance_rune(t)
				continue
			}
			if !(is_dig) {
				break

			}
			if (val >= base) {
				digit_pos := get_pos(t)
				tokenizer_error_at(
					t,
					digit_pos,
					"Value exceeds exceeds '%i', invalid for base '%i'",
					base - 1,
					base,
				)
			}
			advance_rune(t)
		}
	}
	scan_fraction :: proc(t: ^Tokenizer, kind: ^TokenKind) {
		if t.r == '.' {
			kind^ = .Float
			advance_rune(t)
			scan_digits(t, 10)

		}
	}
	int_base :: proc(t: ^Tokenizer, kind: ^TokenKind, base: int, msg: string) {
		prev := t.pos
		advance_rune(t)
		scan_digits(t, base)
		if t.pos - prev <= 1 {
			kind^ = .Invalid
			tokenizer_error_at(t, get_pos(t), msg)
		}
	}


	pos := t.pos
	kind := TokenKind.Int
	switch {
	case start_point:
		kind = .Float
		pos -= 1
		scan_digits(t, 10)

		return kind, string(t.src[pos:t.pos])

	case '0' == t.r:
		advance_rune(t)
		switch t.r {
		case 'b':
			int_base(t, &kind, 2, "illegal binary integer")
		case 's':
			int_base(t, &kind, 6, "illegal seximal integer")
		case 'x':
			int_base(t, &kind, 16, "illegal hex integer")
		case:
			scan_digits(t, 10)
			seen_point := false
			if t.r == '.' {
				seen_point = true
				scan_fraction(t, &kind)

			}
			return kind, string(t.src[pos:t.pos])

		}

	}
	scan_digits(t, 10)
	scan_fraction(t, &kind)


	return kind, string(t.src[pos:t.pos])
}
is_letter :: proc(r: rune) -> bool {
	if r == '_' {return true}
	return unicode.is_letter(r)
}
scan_identifier :: proc(t: ^Tokenizer) -> string {
	pos := t.pos

	for is_letter(t.r) || is_digit_no_val(t.r) {
		advance_rune(t)
	}

	return string(t.src[pos:t.pos])
}
scan :: proc(t: ^Tokenizer) -> Token {
	skip_whitespace(t)
	pos := get_pos(t)
	tok := Token{}

	switch true {
	case t.r == 0:
		tok.kind = .EOF
	case '0' <= t.r && '9' >= t.r:
		tok.kind, tok.lit = scan_number(t)
	case is_letter(t.r):
		tok.kind = .Ident
		tok.lit = scan_identifier(t)
		for i in TokenKind.Begin_Keyword ..= TokenKind.End_Keyword {
			if tok.lit == tokens[i] {
				tok.kind = TokenKind(i)
				break
			}
		}

	case:
		switch t.r {
		case '.':
			advance_rune(t)
			if t.r >= '0' && t.r <= '9' {

				tok.kind, tok.lit = scan_number(t, true)
			}
		case:
			tokenizer_error_at(t, pos, "invalid token")
			os.exit(1)

		}

	}


	return tok
}


skip_whitespace :: proc(t: ^Tokenizer) {
	for unicode.is_white_space(t.r) {advance_rune(t)}
}


skip :: proc(t: ^Tokenizer, text: string) -> bool {
	for r in text {
		if !(t.r == r) {return false}
		advance_rune(t)
	}
	return true
}

tokenizer_error :: proc(t: ^Tokenizer, msg: string, args: ..any) {
	t.nerrors += 1
	col := t.start_line + 1
	fmt.eprintf("%s:%d:%d: ", t.path, t.nlines + 1, col)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
}
tokenizer_error_at :: proc(t: ^Tokenizer, pos: Pos, msg: string, args: ..any) {
	t.nerrors += 1
	rest := t.src[pos.start_line:]
	idx := strings.index_byte(rest, '\n')
	line_text := rest if idx < 0 else rest[:idx]

	fmt.eprintf("%s:%d:%d: ", t.path, pos.line, pos.col)
	fmt.eprintf("\n%s", line_text)
	fmt.printf("\n%*s", pos.pos - pos.start_line, "")
	fmt.printf("^ ")
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")

}
Parser :: struct {
	tok: Tokenizer,
}

parse_file :: proc(p: ^Parser, md: ^Package) {

	t := &p.tok

	advance_rune(t)
	loop: for true {
		tok := scan(t)
		#partial switch tok.kind {
		case .EOF:
			break loop
		case .Invalid:
			fmt.eprintln("pos %v", get_pos(t))
			panic("huh")

		case:
			fmt.eprintln("tok %v", tok)

		}
	}


}

parse_base_module :: proc(cs: ^Compiler_State) {

	append(&cs.modules, Package{})
	for fdt, i in cs.file_data {
		p := &cs.parsers[i]
		t := &p.tok
		t.path = cs.file_names[i]
		t.src = cs.file_data[i]

		parse_file(p, &cs.modules[0])
	}


	sb := strings.Builder{}
	strings.write_string(&sb, cs.modules[0].name)
	strings.write_string(&sb, ".js")

	fp := os.open(strings.to_string(sb), {.Create, .Write}) or_else panic("idk")
	os.write(fp, transmute([]u8)cs.file_data[0])


}


build :: proc(cs: ^Compiler_State) {
	cs.file_data = make(type_of(cs.file_data), len(cs.file_names))
	cs.parsers = make(type_of(cs.parsers), len(cs.file_names))
	for file, i in cs.file_names {
		cs.file_data[i] = string(
			os.read_entire_file(file, context.allocator) or_else panic("Couldn't read files"),
		)


	}
	parse_base_module(cs)

}
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
