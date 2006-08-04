implement Bind;

include "sys.m";
include "draw.m";
include "arg.m";

FD: import Sys;
Context: import Draw;

Bind: module
{
	init:	fn(ctxt: ref Context, args: list of string);
};

sys: Sys;
copt: int;
stderr: ref FD;

init(nil: ref Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	stderr = sys->fildes(2);
	arg := load Arg Arg->PATH;
	if(arg == nil){
		sys->fprint(stderr, "bind: can't load %s: %r\n", Arg->PATH);
		raise "fail:load";
	}

	flags := sys->MREPL;
	arg->init(args);
	while((o := arg->opt()) != 0)
		case o {
		'a' =>
			flags = sys->MAFTER;
		'b' =>
			flags = sys->MBEFORE;
		'c' =>
			copt++;	
		* =>
			usage();
		}
	argv := arg->argv();
	arg = nil;

	if(copt)
		flags |= sys->MCREATE;

	if(len argv != 2)
		usage();

	if(sys->bind(hd argv, hd tl argv, flags) < 0) {
		sys->fprint(stderr, "bind: cannot bind %s onto %s: %r\n", hd argv, hd tl argv);
		raise "fail:bind";
	}
}

usage()
{
	sys->fprint(stderr, "usage: bind [-a|-b|-c|-ac|-bc] source target\n");
	raise "fail:usage";
}
