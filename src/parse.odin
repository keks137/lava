package lava


Parser :: struct {
	tok:  Tokenizer,
	cur:  Token,
	prev: Token,
}
Binary_Expr :: struct {
	op:    TokenKind,
	left:  int,
	right: int,
}

Literal_Expr :: struct {
	kind: TokenKind,
	lit:  string,
}
Expr_Stmt :: struct {
	expr: int,
}
Node_Kind :: enum {
	Invalid,
	Start,
	Binary,
	Literal,
	Expr_Stmt,
}

Node :: struct {
	pos:  Pos,
	kind: Node_Kind,
	data: union {
		Binary_Expr,
		Literal_Expr,
		Expr_Stmt,
	},
}


next :: proc(p: ^Parser) {
	p.prev = p.cur
	p.cur = scan(&p.tok)
}

token_precedence :: proc(kind: TokenKind) -> int {
	#partial switch kind {
	case .Mul, .Div:
		return 2
	case .Add, .Sub:
		return 1
	case:
		return -1
	}
}


info_node :: proc(p: ^Parser, n: Node, msg: string, args: ..any) {

	rest := p.tok.src[n.pos.start_line:]
	idx := strings.index_byte(rest, '\n')
	line_text := rest if idx < 0 else rest[:idx]

	if terminal.color_enabled {
		fmt.print(ansi.CSI + ansi.FG_CYAN + ansi.SGR)
		fmt.print(ansi.CSI + ansi.BOLD + ansi.SGR)
	}
	fmt.printfln("info: ")
	if terminal.color_enabled {
		fmt.print(ansi.CSI + ansi.RESET + ansi.SGR)
	}
	fmt.printf("%s:%d:%d", p.tok.path, n.pos.line, n.pos.col)

	fmt.printf("\n%s", line_text)
	fmt.printf("\n%*s", n.pos.col - 1, "")
	if terminal.color_enabled {
		fmt.print(ansi.CSI + ansi.FG_CYAN + ansi.SGR)
		fmt.print(ansi.CSI + ansi.BOLD + ansi.SGR)
	}
	fmt.printf("^")

	if n.kind == .Literal {
		tok_width := len(n.data.(Literal_Expr).lit)
		if tok_width >= 2 {
			for i in 2 ..< tok_width {
				fmt.printf("~")
			}
			fmt.printf("^")
		}
	}
	fmt.printf(" ")
	fmt.printf(msg, ..args)
	if terminal.color_enabled {
		fmt.print(ansi.CSI + ansi.RESET + ansi.SGR)
	}
	fmt.printf("\n")


}

error_node :: proc(p: ^Parser, n: Node, msg: string, args: ..any) {
	p.tok.nerrors += 1

	rest := p.tok.src[n.pos.start_line:]
	idx := strings.index_byte(rest, '\n')
	line_text := rest if idx < 0 else rest[:idx]

	if terminal.color_enabled {
		fmt.eprint(ansi.CSI + ansi.FG_RED + ansi.SGR)
		fmt.eprint(ansi.CSI + ansi.BOLD + ansi.SGR)
	}
	fmt.eprintfln("error: ")
	if terminal.color_enabled {
		fmt.eprint(ansi.CSI + ansi.RESET + ansi.SGR)
	}
	fmt.eprintf("%s:%d:%d", p.tok.path, n.pos.line, n.pos.col)

	fmt.eprintf("\n%s", line_text)
	fmt.printf("\n%*s", n.pos.col - 1, "")
	if terminal.color_enabled {
		fmt.eprint(ansi.CSI + ansi.FG_RED + ansi.SGR)
		fmt.eprint(ansi.CSI + ansi.BOLD + ansi.SGR)
	}
	fmt.eprintf("^")

	if n.kind == .Literal {
		tok_width := len(n.data.(Literal_Expr).lit)
		if tok_width >= 2 {
			for i in 2 ..< tok_width {
				fmt.eprintf("~")
			}
			fmt.eprintf("^")
		}
	}
	fmt.eprintf(" ")
	fmt.eprintf(msg, ..args)
	if terminal.color_enabled {
		fmt.eprint(ansi.CSI + ansi.RESET + ansi.SGR)
	}
	fmt.eprintf("\n")


}
parse_expr :: proc(p: ^Parser, ast: ^[dynamic]Node, min_prec: int) -> (index: int, ok: bool) {
	left := parse_atom(p, ast) or_return

	for {
		prec := token_precedence(p.cur.kind)
		if prec < min_prec {
			break
		}

		op_tok := p.cur
		op := p.cur.kind
		pos := p.cur.pos
		next(p)

		// prec + 1 makes it left-associative
		right, ok := parse_expr(p, ast, prec + 1)
		if !ok {
			tokenizer_error_tok(&p.tok, op_tok, "missing proper right hand")
			// info_node(p, ast[left], "to this")
		}

		append(
			ast,
			Node {
				pos = pos,
				kind = .Binary,
				data = Binary_Expr{op = op, left = left, right = right},
			},
		)
		left = len(ast) - 1
	}

	return left, true
}

parse_atom :: proc(p: ^Parser, ast: ^[dynamic]Node) -> (index: int, ok: bool) {
	#partial switch p.cur.kind {
	case .Int, .Float:
		idx := len(ast)
		append(
			ast,
			Node {
				pos = p.cur.pos,
				kind = .Literal,
				data = Literal_Expr{kind = p.cur.kind, lit = p.cur.lit},
			},
		)
		next(p)
		return idx, true

	case .OParen:
		next(p)
		idx := parse_expr(p, ast, 0) or_return
		if p.cur.kind != .CParen {
			tokenizer_error_tok(&p.tok, p.cur, "expected ')'")
		} else {
			next(p)
		}
		return idx, true
	case .EOF:
		// 	tokenizer_error_tok(&p.tok, p.cur, "unexpected end of file")
		return 0, false

	case:
		tokenizer_error_tok(&p.tok, p.cur, "expected expression")
		next(p)
		return 0, false
	}
}

parse_stmt :: proc(p: ^Parser, ast: ^[dynamic]Node) -> (index: int, ok: bool) {
	pos := p.cur.pos

	expr_idx := parse_expr(p, ast, 0) or_return

	append(ast, Node{pos = pos, kind = .Expr_Stmt, data = Expr_Stmt{expr = expr_idx}})

	return len(ast) - 1, true
}
parse_file :: proc(p: ^Parser, md: ^Package, cs: ^CompilerState) {

	t := &p.tok

	advance_rune(t)

	tok := scan(t)
	if tok.kind != .Pkg {
		tokenizer_error_tok(t, tok, "expected 'pkg' at start of file")
	}
	tok = scan(t)
	if tok.kind != .Ident {
		tokenizer_error_tok(t, tok, "expected package name")
	}
	if md.name == "" {
		md.name = tok.lit
	}
	if md.name != tok.lit {
		tokenizer_error_tok(t, tok, "Differing package name, other file has '%s'", md.name)
	}


	next(p)
	loop: for true {
		#partial switch p.cur.kind {
		case .EOF:
			break loop
		case .Invalid:
			tokenizer_error_tok(t, p.cur, "invalid token")
			next(p)
		case:
			parse_stmt(p, &cs.ast)
		}
	}


}

parse_base_module :: proc(cs: ^CompilerState) {

	append(&cs.pkgs, Package{})
	append(&cs.ast, Node{kind = .Start})
	for fdt, i in cs.file_data {
		p := &cs.parsers[i]
		t := &p.tok
		t.path = cs.file_names[i]
		t.src = cs.file_data[i]

		parse_file(p, &cs.pkgs[0], cs)
	}


	sb := strings.Builder{}
	if cs.pkgs[0].name == "" {
		panic("Package name is nil")
	}
	strings.write_string(&sb, cs.pkgs[0].name)
	strings.write_string(&sb, ".js")

	fp := os.open(strings.to_string(sb), {.Create, .Write}) or_else panic("idk")
	os.write(fp, transmute([]u8)cs.file_data[0])


}
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:terminal"
import "core:terminal/ansi"
import "core:unicode"
import "core:unicode/utf8"
