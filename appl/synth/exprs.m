Exprs: module {
	PATH : con "/dis/synth/exprs.dis";
	Expr: adt {
		pick {
		String =>
			s: string;
		List =>
			l:	cyclic list of ref Expr;
		}
		islist:	fn(e: self ref Expr): int;
		els:	fn(e: self ref Expr): list of ref Expr;
		op:	fn(e: self ref Expr): string;
		args:	fn(e: self ref Expr): list of ref Expr;
		text:	fn(e: self ref Expr): string;
		parse:fn(args: list of string): ref Expr;
	};
};
