# Gui implementation for running under wm (tk window manager)
implement Gui;

include "common.m";
include "tk.m";
include "tkclient.m";

sys: Sys;

D: Draw;
	Font,Point, Rect, Image, Screen, Display: import D;

CU: CharonUtils;

E: Events;
	Event: import E;

tk: Tk;

tkclient: Tkclient;

WINDOW, CTLS, PROG, STATUS, BORDER, EXIT: con 1 << iota;
REQD: con ~0;

cfg := array[] of {
	(REQD,	"entry .ctlf.url -bg white -font /fonts/lucidasans/unicode.7.font -height 16"),
	(REQD,	"button .ctlf.back -bd 1 -command {send gctl back} -state disabled -text {back} -font /fonts/lucidasans/unicode.7.font"),
	(REQD,	"button .ctlf.stop -bd 1 -command {send gctl stop} -state disabled -text {stop} -font /fonts/lucidasans/unicode.7.font"),
	(REQD,	"button .ctlf.fwd -bd 1 -command {send gctl fwd} -state disabled -text {next} -font /fonts/lucidasans/unicode.7.font"),
	(REQD,	"label .status.status -bd 1 -font /fonts/lucidasans/unicode.6.font -height 14 -anchor w"),
	(REQD,	"button .ctlf.exit -bd 1 -bitmap exit.bit -command {send wm_title exit}"),
	(REQD,	"frame .f -bd 0"),
	(BORDER,	".f configure -bd 2 -relief sunken"),
	(CTLS|EXIT,	"frame .ctlf"),
	(STATUS,	"frame .status -bd 0"),
	(STATUS,	"frame .statussep -bg black -height 1"),
	(STATUS,	"button .status.snarf -text snarf -command {send gctl snarfstatus} -font /fonts/charon/plain.small.font"),

	(CTLS,	"bind .ctlf.url <Key-\n> {send gctl go}"),
	(CTLS,	"bind .ctlf.url <Key-\u0003> {send gctl copyurl}"),
	(CTLS,	"bind .ctlf.url <Key-\u0016> {send gctl pasteurl}"),

#	(PROG,	"canvas .prog -bd 0 -height 20"),
#	(PROG,	"bind .prog <ButtonPress-1> {send gctl b1p %X %Y}"),
	(CTLS,	"pack .ctlf.back .ctlf.stop .ctlf.fwd -side left -anchor w -fill y"),
	(CTLS,	"pack .ctlf.url -side left -padx 2 -fill x -expand 1"),
	(EXIT,	"pack .ctlf.exit -side right -anchor e"),
	(CTLS|EXIT,	"pack .ctlf -side top -fill x"),
	(REQD,	"pack .f -side top -fill both -expand 1"),
#	(PROG,	"pack .prog -side bottom -fill x"),
	(STATUS,	"pack .status.snarf -side right"),
	(STATUS,	"pack .status.status -side right -fill x -expand 1"),
	(STATUS,	"pack .statussep -side top -fill x"),
	(STATUS,	"pack .status -side bottom -fill x"),
	(CTLS|EXIT,	"pack propagate .ctlf 0"),
	(STATUS,		"pack propagate .status 0"),
};

framebinds := array[] of {
	"bind .f <Key> {send gctl k %s}",
	"bind .f <FocusOut> {send gctl focusout}",
	"bind .f <ButtonPress-1> {grab set .f;send gctl b1p %X %Y}",
	"bind .f <Double-ButtonPress-1> {send gctl b1p %X %Y}",
	"bind .f <ButtonRelease-1> {grab release .f;send gctl b1r %X %Y}",
	"bind .f <Motion-Button-1> {send gctl b1d %X %Y}",
	"bind .f <ButtonPress-2> {send gctl b2p %X %Y}",
	"bind .f <Double-ButtonPress-2> {send gctl b2p %X %Y}",
	"bind .f <ButtonRelease-2> {send gctl b2r %X %Y}",
	"bind .f <Motion-Button-2> {send gctl b2d %X %Y}",
	"bind .f <ButtonPress-3> {send gctl b3p %X %Y}",
	"bind .f <Double-ButtonPress-3> {send gctl b3p %X %Y}",
	"bind .f <ButtonRelease-3> {send gctl b3r %X %Y}",
	"bind .f <Motion-Button-3> {send gctl b3d %X %Y}",
	"bind .f <Motion> {send gctl m %X %Y}",
};

tktop: ref Tk->Toplevel;
mousegrabbed := 0;
offset: Point;
ZP: con Point(0,0);
popup: ref Popup;
popuptk: ref Tk->Toplevel;
gctl: chan of string;
drawctxt: ref Draw->Context;

realwin: ref Draw->Image;
mask: ref Draw->Image;

init(ctxt: ref Draw->Context, cu: CharonUtils): ref Draw->Context
{
	sys = load Sys Sys->PATH;
	D = load Draw Draw->PATH;
	CU = cu;
	E = cu->E;
	if((CU->config).doacme){
		display=ctxt.display;
		makewins();
		progress = chan of Progressmsg;
		pidc := chan of int;
		spawn doacmeprogmon(pidc);
		<- pidc;
		return ctxt;
	}
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if(tkclient == nil)
		CU->raisex(sys->sprint("EXInternal: can't load module Tkclient: %r"));
	tkclient->init();
	if (ctxt == nil)
		ctxt = tkclient->makedrawcontext();
	if(ctxt == nil)
		CU->raisex(sys->sprint("charon: no window context\n"));

	wmctl: chan of string;
	buttons := parsebuttons((CU->config).buttons);
	winopts := parsewinopts((CU->config).framework);

	(tktop, wmctl) = tkclient->toplevel(ctxt, "", (CU->config).wintitle, buttons);

	ctxt = tktop.ctxt.ctxt;
	drawctxt = ctxt;
	display = ctxt.display;

	gctl = chan of string;
	tk->namechan(tktop, gctl, "gctl");
	tk->cmd(tktop, "pack propagate . 0");
	filtertkcmds(tktop, winopts, cfg);
	tkcmds(tktop, framebinds);
	w := (CU->config).defaultwidth;
	h := (CU->config).defaultheight;
	tk->cmd(tktop, ". configure -width " + string w + " -height " + string h);
	tk->cmd(tktop, "update");
	tkclient->onscreen(tktop, nil);
	tkclient->startinput(tktop, "kbd"::"ptr"::nil);
	makewins();
	mask = display.opaque;
	progress = chan of Progressmsg;
	pidc := chan of int;
	spawn progmon(pidc);
	<- pidc;
	spawn evhandle(tktop, wmctl, E->evchan);
	return ctxt;
}

parsebuttons(s: string): int
{
	b := 0;
	(nil, toks) := sys->tokenize(s, ",");
	for (;toks != nil; toks = tl toks) {
		case hd toks {
		"help" =>
			b |= Tkclient->Help;
		"resize" =>
			b |= Tkclient->Resize;
		"hide" =>
			b |= Tkclient->Hide;
		"plain" =>
			b = Tkclient->Plain;
		}
	}
	return b | Tkclient->Help;
}

parsewinopts(s: string): int
{
	b := WINDOW;
	(nil, toks) := sys->tokenize(s, ",");
	for (;toks != nil; toks = tl toks) {
		case hd toks {
		"status" =>
			b |= STATUS;
		"controls" or "ctls" =>
			b |= CTLS;
		"progress" or "prog" =>
			b |= PROG;
		"border" =>
			b |= BORDER;
		"exit" =>
			b |= EXIT;
		"all" =>
			# note: "all" doesn't include 'EXIT' !
			b |= WINDOW | STATUS | CTLS | PROG | BORDER;
		}
	}
	return b;
}

filtertkcmds(top: ref Tk->Toplevel, filter: int, cmds: array of (int, string))
{
	for (i := 0; i < len cmds; i++) {
		(val, cmd) := cmds[i];
		if (val & filter) {
			if ((e := tk->cmd(top, cmd)) != nil && e[0] == '!')
				sys->print("tk error on '%s': %s\n", cmd, e);
		}
	}
}

tkcmds(top: ref Tk->Toplevel, cmds: array of string)
{
	for (i := 0; i < len cmds; i++)
		if ((e := tk->cmd(top, cmds[i])) != nil && e[0] == '!')
			sys->print("tk error on '%s': %s\n", cmds[i], e);
}

clientr(t: ref Tk->Toplevel, wname: string): Rect
{
	bd := int tk->cmd(t, wname + " cget -borderwidth");
	x := bd + int tk->cmd(t, wname + " cget -actx");
	y := bd + int tk->cmd(t, wname + " cget -acty");
	w := int tk->cmd(t, wname + " cget -actwidth");
	h := int tk->cmd(t, wname + " cget -actheight");
	return Rect((x,y),(x+w,y+h));
}

doacmeprogmon(pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for (;;) {
		<- progress;
	}
}

progmon(pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for (;;) {
		msg := <- progress;
#prprog(msg);
		# just handle stop button for now
		if (msg.bsid == -1) {
			case (msg.state) {
			Pstart =>	stopbutton(1);
			* =>		stopbutton(0);
			}
		}
	}
}

st2s := array [] of {
	Punused => "unused",
	Pstart => "start",
	Pconnected => "connected",
	Psslconnected => "sslconnected",
	Phavehdr => "havehdr",
	Phavedata => "havedata",
	Pdone => "done",
	Perr => "error",
	Paborted => "aborted",
};

prprog(m:Progressmsg)
{
	sys->print("%d %s %d%% %s\n", m.bsid, st2s[m.state], m.pcnt, m.s);
}


r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

winpos(t: ref Tk->Toplevel): Point
{
	return (int tk->cmd(t, ". cget -actx"), int tk->cmd(t, ". cget -acty"));
}

evhandle(t: ref Tk->Toplevel, wmctl: chan of string, evchan: chan of ref Event)
{
	for(;;) {
		ev: ref Event = nil;
		dismisspopup := 1;
		alt {
		s := <-gctl =>
			(nil, l) := sys->tokenize(s, " ");
			case hd l {
			"focusout" =>
				ev = ref Event.Elostfocus;
			"b1p" or "b1r" or "b1d" or 
			"b2p" or "b2r" or "b2d" or 
			"b3p" or "b3r" or "b3d" or 
			"m" =>
				l = tl l;
				pt := Point(int hd l, int hd tl l);
				pt = pt.sub(offset);
				mtype := s2mtype(s);
				dismisspopup = 0;
				if(mtype == E->Mlbuttondown) {
					tk->cmd(t, "focus .f");
					pu := popup;
					if (pu != nil && !pu.r.contains(pt))
						dismisspopup = 1;
					pu = nil;
				}
				ev = ref Event.Emouse(pt, mtype);
			"k" =>
				dismisspopup = 0;
				k := int hd tl l;
				if(k != 0)
					ev = ref Event.Ekey(k);
			"back" =>
				ev = ref Event.Eback;
			"stop" =>
				ev = ref Event.Estop;
			"fwd" =>
				ev = ref Event.Efwd;
			"go" =>
				url := tk->cmd(tktop, ".ctlf.url get");
				if (url != nil)
					ev = ref Event.Ego(url, nil, 0, E->EGnormal);
			"copyurl" =>
				url := tk->cmd(tktop, ".ctlf.url get");
				snarfput(url);
			"pasteurl" =>
				url := tk->quote(tkclient->snarfget());
				tk->cmd(tktop, ".ctlf.url delete 0 end");
				tk->cmd(tktop, ".ctlf.url insert end " + url);
				tkupdate();
			"snarfstatus" =>
				url := tk->cmd(tktop, ".status.status cget -text");
				tkclient->snarfput(url);
			}
		s := <-t.ctxt.ctl or
		s = <-t.wreq or
		s = <-wmctl =>
			case s {
			"exit" =>
				hidewins();
				ev = ref Event.Equit(0);
			"task" =>
				if (cancelpopup())
					evchan <-= ref Event.Edismisspopup;
				tkclient->wmctl(t, s);
				if(tktop.image == nil)
					realwin = nil;
			"help" =>
				ev = ref Event.Ego((CU->config).helpurl, nil, 0, E->EGnormal);
			* =>
				if (s[0] == '!' && cancelpopup())
					evchan <-= ref Event.Edismisspopup;
				oldimg := t.image;
				e := tkclient->wmctl(t, s);
				if(s[0] == '!' && e == nil){
					if(t.image != oldimg){
						oldimg = nil;
						makewins();
						ev = ref Event.Ereshape(mainwin.r);
					}
					offset = tk->rect(tktop, ".f", 0).min;
				}
			}
		s := <-t.ctxt.kbd =>
			tk->keyboard(t, s);
		s := <-t.ctxt.ptr =>
			tk->pointer(t, *s);
		}
		if (dismisspopup) {
			if (cancelpopup()) {
				evchan <-= ref Event.Edismisspopup;
			}
		}
		if (ev != nil)
			evchan <-= ev;
	}
}

s2mtype(s: string): int
{
	mtype := E->Mmove;
	if(s[0] == 'm')
		mtype = E->Mmove;
	else {
		case s[1] {
		'1' =>
			case s[2] {
			'p' => mtype = E->Mlbuttondown;
			'r' => mtype = E->Mlbuttonup;
			'd' => mtype = E->Mldrag;
			}
		'2' =>
			case s[2] {
			'p' => mtype = E->Mmbuttondown;
			'r' => mtype = E->Mmbuttonup;
			'd' => mtype = E->Mmdrag;
			}
		'3' =>
			case s[2] {
			'p' => mtype = E->Mrbuttondown;
			'r' => mtype = E->Mrbuttonup;
			'd' => mtype = E->Mrdrag;
			}
		}
	}
	return mtype;
}

makewins()
{
	if((CU->config).doacme){
		mainwin = display.newimage(Rect(display.image.r.min, ((CU->config).defaultwidth, display.image.r.max.y)), display.image.chans, 0, D->White);
		return;
		if(mainwin == nil)
			CU->raisex(sys->sprint("EXFatal: can't initialize windows: %r"));
	}
	if(tktop.image == nil)
		return;
	screen := Screen.allocate(tktop.image, display.transparent, 0);
	offset = tk->rect(tktop, ".f", 0).min;
	r := tk->rect(tktop, ".f", Tk->Local);
	realwin = screen.newwindow(r, D->Refnone, D->White);
	realwin.origin(ZP, r.min);
	if(realwin == nil)
		CU->raisex(sys->sprint("EXFatal: can't initialize windows: %r"));

	mainwin = display.newimage(realwin.r, realwin.chans, 0, D->White);
	if(mainwin == nil)
		CU->raisex(sys->sprint("EXFatal: can't initialize windows: %r"));
}

hidewins()
{
	if((CU->config).doacme)
		return;
	tk->cmd(tktop, ". unmap");
}

snarfput(s: string)
{
	if((CU->config).doacme)
		return;
	tkclient->snarfput(s);
}

setstatus(s: string)
{
	if((CU->config).doacme)
		return;
	tk->cmd(tktop, ".status.status configure -text " + tk->quote(s));
	tkupdate();
}

seturl(s: string)
{
	if((CU->config).doacme)
		return;
	tk->cmd(tktop, ".ctlf.url delete 0 end");
	tk->cmd(tktop, ".ctlf.url insert 0 " + tk->quote(s));
	tkupdate();
}

auth(realm: string): (int, string, string)
{
	user := prompt(realm + " username?", nil).t1;
	passwd := prompt("password?", nil).t1;
	if(user == nil)
		return (0, nil, nil);
	return (1, user, passwd);
}

alert(msg: string)
{
sys->print("ALERT:%s\n", msg);
	return;
}

confirm(msg: string): int
{
sys->print("CONFIRM:%s\n", msg);
	return -1;
}

prompt(msg, nil: string): (int, string)
{
	if((CU->config).doacme)
		return (-1, "");
	return (-1, "");
}

stopbutton(enable: int)
{
	if((CU->config).doacme)
		return;
	state: string;
	if (enable) {
		tk->cmd(tktop, ".ctlf.stop configure -bg red -activebackground red -activeforeground white");
		state = "normal";
	} else {
		tk->cmd(tktop, ".ctlf.stop configure -bg #dddddd");
		state = "disabled";
	}
	tk->cmd(tktop, ".ctlf.stop configure -state " + state );
	tkupdate();
}

backbutton(enable: int)
{
	if((CU->config).doacme)
		return;
	state: string;
	if (enable) {
		tk->cmd(tktop, ".ctlf.back configure -bg lime -activebackground lime -activeforeground red");
		state = "normal";
	} else {
		tk->cmd(tktop, ".ctlf.back configure -bg #dddddd");
		state = "disabled";
	}
	tk->cmd(tktop, ".ctlf.back configure -state " + state);
	tkupdate();
}

fwdbutton(enable: int)
{
	if((CU->config).doacme)
		return;
	state: string;
	if (enable) {
		tk->cmd(tktop, ".ctlf.fwd  configure -bg lime -activebackground lime -activeforeground red");
		state = "normal";
	} else {
		tk->cmd(tktop, ".ctlf.fwd configure -bg #dddddd");
		state = "disabled";
	}
	tk->cmd(tktop, ".ctlf.fwd configure -state " + state);
	tkupdate();
}

flush(r: Rect)
{
	if((CU->config).doacme)
		return;
	if(realwin != nil) {
		oclipr := mainwin.clipr;
		mainwin.clipr = r;
		if(!(CU->config).doacme)
			realwin.draw(r, mainwin, nil, r.min);
		mainwin.clipr = oclipr;
	}
}

clientfocus()
{
	if((CU->config).doacme)
		return;
	tk->cmd(tktop, "focus .f");
	tkupdate();
}

exitcharon()
{
	hidewins();
	E->evchan <-= ref Event.Equit(0);
}

tkupdate()
{

	if(!(CU->config).doacme)
		tk->cmd(tktop, "update");
}

getpopup(nil: Rect): ref Popup
{
	return nil;
}

cancelpopup(): int
{
	popuptk = nil;
	pu := popup;
	if (pu == nil)
		return 0;
	pu.image = nil;
	pu.window = nil;
	pu = nil;
	popup = nil;
	return 1;
}

Popup.flush(p: self ref Popup, r: Rect)
{
	win := p.window;
	img := p.image;
	if (win != nil && img != nil)
		win.draw(r, img, nil, r.min);
}
