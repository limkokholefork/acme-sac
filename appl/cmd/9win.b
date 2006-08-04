implement Ninewin;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Image, Display, Pointer: import draw;
include "keyboard.m";
include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;
include "sh.m";
	sh: Sh;

# run a p9 graphics program (default rio) under plan 9,
# making available to it:
# /dev/winname - naming the current inferno window (changing on resize)
# /dev/mouse - pointer file + resize events.
# /dev/draw - inferno draw device
# /dev/cons - read keyboard events, write to 9win stdout.

Ninewin: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};
winname: string;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	wmclient->init();
	sh = load Sh Sh->PATH;

	buts := Wmclient->Resize;
	if(ctxt == nil){
		ctxt = wmclient->makedrawcontext();
		buts = Wmclient->Plain;
	}
	argv = tl argv;
	if(argv == nil)
		argv = "rio" :: nil;
	w := wmclient->window(ctxt, "9win "+hd argv, buts);
	w.reshape(((0, 0), (500, 500)));
	w.onscreen(nil);
	if(w.image == nil){
		sys->fprint(sys->fildes(2), "9win: cannot get image to draw on\n");
		raise "fail:no window";
	}

	sys->pctl(Sys->FORKNS|Sys->NEWPGRP, nil);
	w.startinput("kbd" :: "ptr" :: nil);
	spawn ptrproc(rq := chan of Sys->Rread, ptr := chan[10] of ref Pointer, reshape := chan[1] of int);

	sys->bind("#s", "/n/local", Sys->MREPL);
	fwinname := sys->file2chan("/n/local", "winname");
	fconsctl := sys->file2chan("/n/local", "consctl");
	fcons := sys->file2chan("/n/local", "cons");
	fmouse := sys->file2chan("/n/local", "mouse");
	spawn run(sync := chan of string, w.ctl, argv);
	if((e := <-sync) != nil){
		sys->fprint(sys->fildes(2), "9win: %s", e);
		raise "fail:error";
	}
	spawn serveproc(w, rq, fwinname, fconsctl, fcons, fmouse);
	# handle events synchronously so that we don't get a "killed" message
	# from the shell.
	handleevents(w, ptr, reshape);
}

handleevents(w: ref Window, ptr: chan of ref Pointer, reshape: chan of int)
{
	for(;;)alt{
	c := <-w.ctxt.ctl or
	c = <-w.ctl =>
		e := w.wmctl(c);
		if(e != nil)
			sys->fprint(sys->fildes(2), "9win: ctl error: %s\n", e);
		if(e == nil && c != nil && c[0] == '!'){
			alt{
			reshape <-= 1 =>
				;
			* =>
				;
			}
			winname = nil;
		}
	p := <-w.ctxt.ptr =>
		if(w.pointer(*p) == 0){
			# XXX would block here if client isn't reading mouse... but we do want to
			# extert back-pressure, which conflicts.
			alt{
			ptr <-= p =>
				;
			* =>
				; # sys->fprint(sys->fildes(2), "9win: discarding mouse event\n");
			}
		}
	}
}

serveproc(w: ref Window, mouserq: chan of Sys->Rread, fwinname, fconsctl, fcons, fmouse: ref Sys->FileIO)
{
	winid := 0;
	krc: list of Sys->Rread;
	ks: string;

	for(;;)alt {
	c := <-w.ctxt.kbd =>
		ks[len ks] = inf2p9key(c);
		if(krc != nil){
			hd krc <-= (array of byte ks, nil);
			ks = nil;
			krc = tl krc;
		}
	(nil, d, nil, wc) := <-fcons.write =>
		if(wc != nil){
			sys->write(sys->fildes(1), d, len d);
			wc <-= (len d, nil);
		}
	(nil, nil, nil, rc) := <-fcons.read =>
		if(rc != nil){
			if(ks != nil){
				rc <-= (array of byte ks, nil);
				ks = nil;
			}else
				krc = rc :: krc;
		}
	(offset, nil, nil, rc) := <-fwinname.read =>
		if(rc != nil){
			if(winname == nil){
				winname = sys->sprint("noborder.9win.%d", winid++);
				if(w.image.name(winname, 1) == -1){
					sys->fprint(sys->fildes(2), "9win: namewin %q failed: %r", winname);
					rc <-= (nil, "namewin failure");
					break;
				}
			}
			d := array of byte winname;
			if(offset < len d)
				d = d[offset:];
			else
				d = nil;
			rc <-= (d, nil);
		}
	(nil, nil, nil, wc) := <-fwinname.write =>
		if(wc != nil)
			wc <-= (-1, "permission denied");
	(nil, nil, nil, rc) := <-fconsctl.read =>
		if(rc != nil)
			rc <-= (nil, "permission denied");
	(nil, d, nil, wc) := <-fconsctl.write =>
		if(wc != nil){
			if(string d != "rawon")
				wc <-= (-1, "cannot change console mode");
			else
				wc <-= (len d, nil);
		}
	(nil, nil, nil, rc) := <-fmouse.read =>
		if(rc != nil)
			mouserq <-= rc;
	(nil, nil, nil, wc) := <-fmouse.write =>
		if(wc != nil)
			wc <-= (-1, "permission denied");
	}
}

ptrproc(rq: chan of Sys->Rread, ptr: chan of ref Pointer, reshape: chan of int)
{
	rl: list of Sys->Rread;
	c := ref Pointer(0, (0, 0), 0);
	for(;;){
		ch: int;
		alt{
		p := <-ptr =>
			ch = 'm';
			c = p;
		<-reshape =>
			ch = 'r';
		rc := <-rq =>
			rl  = rc :: rl;
			continue;
		}
		if(rl == nil)
			rl = <-rq :: rl;
		hd rl <-= (sys->aprint("%c%11d %11d %11d %11d ", ch, c.xy.x, c.xy.y, c.buttons, c.msec), nil);
		rl = tl rl;
	}
}

run(sync, ctl: chan of string, argv: list of string)
{
	Rcmeta: con "|<>&^*[]?();";
	sys->pctl(Sys->FORKNS, nil);
	if(sys->bind("#₪", "/srv", Sys->MCREATE) == -1){
		sync <-= sys->sprint("cannot bind srv device: %r");
		exit;
	}
	srvname := "/srv/9win."+string sys->pctl(0, nil);	# XXX do better.
	fd := sys->create(srvname, Sys->ORDWR, 8r600);
	if(fd == nil){
		sync <-= sys->sprint("cannot create %s: %r", srvname);
		exit;
	}
	sync <-= nil;
	spawn export(fd, ctl);
	# XXX /mnt/term is probably a bad choice - what would be better?
	sh->run(nil, "os" ::
		"rc" :: "-c" ::
			"mount "+srvname+" /mnt/term;"+
			"rm "+srvname+";"+
			"bind -b /mnt/term/n/local /dev;"+
			"bind /mnt/term/dev/draw /dev/draw || {mntgen /dev; bind /mnt/term/dev/draw /dev/draw};"+
			quotedc("cd"::"/mnt/term"+cwd()::nil, Rcmeta)+";"+
			quotedc(argv, Rcmeta)+";"::
			nil
		);
}

export(fd: ref Sys->FD, ctl: chan of string)
{
	sys->export(fd, "/", Sys->EXPWAIT);
	ctl <-= "exit";
}

inf2p9key(c: int): int
{
	KF: import Keyboard;

	P9KF: con	16rF000;
	Spec: con	16rF800;
	Khome: con	P9KF|16r0D;
	Kup: con	P9KF|16r0E;
	Kpgup: con	P9KF|16r0F;
	Kprint: con	P9KF|16r10;
	Kleft: con	P9KF|16r11;
	Kright: con	P9KF|16r12;
	Kdown: con	Spec|16r00;
	Kview: con	Spec|16r00;
	Kpgdown: con	P9KF|16r13;
	Kins: con	P9KF|16r14;
	Kend: con	P9KF|16r18;
	Kalt: con		P9KF|16r15;
	Kshift: con	P9KF|16r16;
	Kctl: con		P9KF|16r17;

	case c {
	Keyboard->LShift =>
		return Kshift;
	Keyboard->LCtrl =>
		return Kctl;
	Keyboard->LAlt =>
		return Kalt;
	Keyboard->Home =>
		return Khome;
	Keyboard->End =>
		return Kend;
	Keyboard->Up =>
		return Kup;
	Keyboard->Down =>
		return Kdown;
	Keyboard->Left =>
		return Kleft;
	Keyboard->Right =>
		return Kright;
	Keyboard->Pgup =>
		return Kpgup;
	Keyboard->Pgdown =>
		return Kpgdown;
	Keyboard->Ins =>
		return Kins;

	# function keys
	KF|1 or
	KF|2 or
	KF|3 or
	KF|4 or
	KF|5 or
	KF|6 or
	KF|7 or
	KF|8 or
	KF|9 or
	KF|10 or
	KF|11 or
	KF|12 =>
		return (c - KF) + P9KF;
	}
	return c;
}

cwd(): string
{
	return sys->fd2path(sys->open(".", Sys->OREAD));
}

# from string.b, waiting for declaration to be uncommented.
quotedc(argv: list of string, cl: string): string
{
	s := "";
	while (argv != nil) {
		arg := hd argv;
		for (i := 0; i < len arg; i++) {
			c := arg[i];
			if (c == ' ' || c == '\t' || c == '\n' || c == '\'' || in(c, cl))
				break;
		}
		if (i < len arg || arg == nil) {
			s += "'" + arg[0:i];
			for (; i < len arg; i++) {
				if (arg[i] == '\'')
					s[len s] = '\'';
				s[len s] = arg[i];
			}
			s[len s] = '\'';
		} else
			s += arg;
		if (tl argv != nil)
			s[len s] = ' ';
		argv = tl argv;
	}
	return s;
}

in(c: int, s: string): int
{
	n := len s;
	if(n == 0)
		return 0;
	ans := 0;
	negate := 0;
	if(s[0] == '^') {
		negate = 1;
		s = s[1:];
		n--;
	}
	for(i := 0; i < n; i++) {
		if(s[i] == '-' && i > 0 && i < n-1)  {
			if(c >= s[i-1] && c <= s[i+1]) {
				ans = 1;
				break;
			}
			i++;
		}
		else
		if(c == s[i]) {
			ans = 1;
			break;
		}
	}
	if(negate)
		ans = !ans;
	return ans;
}
