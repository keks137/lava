package main

Compiler_State :: struct {
	file_names: [dynamic]string,
	file_data:  [dynamic]string,
	modules:    [dynamic]Module,
}
Module :: struct {
	name: string,
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
	if t.rpos >= len(t.src) {return}

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
tokenizer_error_at :: proc(t: ^Tokenizer, loc: int, msg: string, args: ..any) {
	t.nerrors += 1
	col := loc - t.start_line + 1
	rest := t.src[t.start_line:]
	idx := strings.index_byte(rest, '\n')
	line_text := rest if idx < 0 else rest[:idx]

	fmt.eprintf("%s:%d:%d: ", t.path, t.nlines + 1, col)
	fmt.eprintf("\n%s", line_text)
	fmt.printf("\n%*s", loc - t.start_line, "")
	fmt.printf("^ ")
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")

}

parse_file :: proc(t: ^Tokenizer, md: ^Module) {

	advance_rune(t)
	skip_whitespace(t)
	pos := t.pos
	if !skip(t, "pkg") {tokenizer_error_at(t, pos, "no package defined")}
	skip_whitespace(t)

	// TODO: error if EOF here

	pkg_name_b := strings.Builder{}
	for {
		strings.write_rune(&pkg_name_b, t.r)
		advance_rune(t)
		if unicode.is_white_space(t.r) {break}
	}
	pkg_name := strings.to_string(pkg_name_b)
	if md.name == "" {
		md.name = pkg_name
	}


	// fmt.printfln("%s", pkg_name)


}

parse_base_module :: proc(cs: ^Compiler_State) {

	append(&cs.modules, Module{})
	for fdt, i in cs.file_data {
		t: Tokenizer = {}
		t.path = cs.file_names[i]
		t.src = cs.file_data[i]

		parse_file(&t, &cs.modules[0])
	}


	fp := os.open("out.js", {.Create, .Write}) or_else panic("idk")
	os.write(fp, transmute([]u8)cs.file_data[0])


}


build :: proc(cs: ^Compiler_State) {
	cs.file_data = make(type_of(cs.file_data), len(cs.file_names))
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
