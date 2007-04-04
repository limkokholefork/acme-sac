implement Exprs;

include "sys.m";
	sys: Sys;
include "exprs.m";

WORD: con iota;
	
Evalstate: adt {
	s:	string;
	spos: int;
	
	expr: fn(p: self ref Evalstate): ref Expr;
	getc: fn(p: self ref Evalstate): int;
	ungetc: fn(p: self ref Evalstate);
	gettok: fn(p: self ref Evalstate): (int, string);
};

Expr.parse(argv: list of string): ref Expr
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	s := hd argv;
	if(tl argv == nil && s != nil && s[0] == '{' && s[len s - 1] == '}')
		s = "void " + hd argv;
	else {
		s = "void {" + hd argv;
		for(argv = tl argv; argv != nil; argv = tl argv){
			a := hd argv;
			if(a == nil || a[0] != '{')		# }
				s += sys->sprint(" %q", a);
			else
				s += " " + hd argv;
		}
		s += "}";
	}
	e := ref Evalstate(s, 0);
	result := e.expr();
	return hd result.args();
}

Expr.islist(e: self ref Expr): int
{
	return e != nil && tagof e == tagof Expr.List;
}

Expr.els(e: self ref Expr): list of ref Expr
{
	if(e == nil)
		return nil;
	pick s := e {
	List =>
		return s.l;
	* =>
		return nil;
	}
}

Expr.op(e: self ref Expr): string
{
	if(e == nil)
		return nil;
	pick s := e {
	String =>
		return s.s;
	List =>
		if(s.l == nil)
			return nil;
		pick t := hd s.l {
		String =>
			return t.s;
		* =>
			return nil;
		}
	}
	return nil;
}

Expr.args(e: self ref Expr): list of ref Expr
{
	if((l := e.els()) != nil)
		return tl l;
	return nil;
}

Expr.text(e: self ref Expr): string
{
	if(e == nil)
		return "";
	pick r := e{
	String =>
		s := sys->sprint("%q", r.s);
		return s;
	List =>
		s := "{";
		for(l := r.l; l != nil; l = tl l){
			s += (hd l).text();
			if(tl l != nil)
				s += " ";
		}
		return s+"}";
	}
}

tok2s(t: int, s: string): string
{
	case t {
	WORD =>
		return s;
	}
	return sys->sprint("%c", t);
}

# expr: WORD exprs
# exprs:
#	| exprs '{' expr '}'
#	| exprs WORD
Evalstate.expr(p: self ref Evalstate): ref Expr
{
	args: list of ref Expr;
	t: int;
	s: string;
	{
		(t, s) = p.gettok();
	} exception e {
	"parse error" =>
		e = e;
		return nil;
	}
	if(t != WORD){
		sys->fprint(stderr(), "fs: eval: syntax error (char %d), expected word, found %#q\n",
				p.spos, tok2s(t, s));
		return nil;
	}
#	cmd := s;
	args = ref Expr.String(s) :: args;
loop:
	for(;;){
		{
			(t, s) = p.gettok();
		} exception e {
		"parse error" =>
			e = e;
			return nil;
		}
		case t {
		'{' =>
			v := p.expr();
			if(v == nil){
				return nil;
			}
			args = v :: args;
		'}' =>
			break loop;
		WORD =>
			args = ref Expr.String(s) :: args;
		-1 =>
			break loop;
		* =>
			sys->fprint(stderr(), "fs: eval: syntax error; unexpected token %d before char %d\n", t, p.spos);
			return nil;
		}
	}
	return ref Expr.List(rev(args));
}

Evalstate.getc(p: self ref Evalstate): int
{
	c := -1;
	if(p.spos < len p.s)
		c = p.s[p.spos];
	p.spos++;
	return c;
}

Evalstate.ungetc(p: self ref Evalstate)
{
	p.spos--;
}

# XXX backslash escapes newline?
Evalstate.gettok(p: self ref Evalstate): (int, string)
{
	while ((c := p.getc()) == ' ' || c == '\t')
		;
	t: int;
	s: string;

	case c {
	-1 =>
		t = -1;
	'\n' =>
		t = '\n';
	'{' =>
		t = '{';
	'}' =>
		t = '}';
	'\'' =>
		s = getqword(p, 0);
		t = WORD;
	* =>
		do {
			s[len s] = c;
			c = p.getc();
			if (in(c, " \t{}\n")){
				p.ungetc();
				break;
			}
		} while (c >= 0);
		t = WORD;
	}
	return (t, s);
}

in(c: int, s: string): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return 1;
	return 0;
}

# get a quoted word; the starting quote has already been seen
getqword(p: ref Evalstate, keepq: int): string
{
	s := "";
	for(;;) {
		while ((nc := p.getc()) != '\'' && nc >= 0)
			s[len s] = nc;
		if (nc == -1){
			sys->fprint(stderr(), "fs: eval: unterminated quote\n");
			raise "parse error";
		}
		if (p.getc() != '\'') {
			p.ungetc();
			if(keepq)
				s[len s] = '\'';
			return s;
		}
		s[len s] = '\'';	# 'xxx''yyy' becomes WORD(xxx'yyy)
		if(keepq)
			s[len s] = '\'';
	}
}

rev[T](x: list of T): list of T
{
	l: list of T;
	for(; x != nil; x = tl x)
		l = hd x :: l;
	return l;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
