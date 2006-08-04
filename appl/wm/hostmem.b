implement Hostmem;

include "sys.m";
	sys: Sys;
	open, read, tokenize, OREAD: import sys;

include "draw.m";
	draw: Draw;

include "tk.m";
	tk: Tk;

include	"tkclient.m";
	tkclient: Tkclient;

include "daytime.m";
	daytime: Daytime;


Hostmem: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

tpid: int;

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys  = load Sys  Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "date: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	tkclient= load Tkclient Tkclient->PATH;
	daytime = load Daytime Daytime->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	tkclient->init();
	(t, wmctl) := tkclient->toplevel(ctxt, "", "Date", 0);

	st := getload();
	tk->cmd(t, "label .d -label {"+st+"}");
	tk->cmd(t, "pack .d; pack propagate . 0");
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "ptr"::nil);
	tick := chan of int;
	spawn timer(tick);

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-wmctl =>
		tkclient->wmctl(t, s);
	<-tick =>
		tk->cmd(t, ".d configure -label {"+getload()+"};update");
	}
}

timer(c: chan of int)
{
	tpid = sys->pctl(0, nil);
	for(;;) {
		c <-= 1;
		sys->sleep(1000 * 5);
	}
}

kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
}

getload(): string
{
	fd := open("#a/hostmem", OREAD);
	if(fd == nil)
		return "";
	b := array[16] of byte;
	read(fd, b, len b);
	(m, fl) := tokenize(string b, " \t\n\r");
	if(m >=2)
		return hd tl fl;
	else
		return "";
}
