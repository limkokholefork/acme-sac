implement View;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Context, Rect, Point, Display, Screen, Image: import draw;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";
	imageremap: Imageremap;
	readgif: RImagefile;
	readjpg: RImagefile;
	readxbitmap: RImagefile;
	readpng: RImagefile;
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;
include "menuhit.m";
	menuhit: Menuhit;
	Menu, Mousectl: import menuhit;

include "selectfile.m";
	selectfile: Selectfile;

include	"arg.m";

include	"plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;

stderr: ref Sys->FD;
display: ref Display;
x := 25;
y := 25;
img_patterns: list of string;
plumbed := 0;
background: ref Image;

View: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv: list of string)
{
	spawn realinit(ctxt, argv);
}

menu: ref Menu;

realinit(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "view: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menuhit = load Menuhit Menuhit->PATH;
	menu = ref Menu(array[] of {"exit"}, nil, 0);
	selectfile = load Selectfile Selectfile->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	selectfile->init();
	wmclient->init();

	stderr = sys->fildes(2);
	display = ctxt.display;
	background = display.color(16r222222ff);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		badload(Arg->PATH);

	img_patterns = list of {
		"*.bit (Compressed image files)",
		"*.gif (GIF image files)",
		"*.jpg (JPEG image files)",
		"*.jpeg (JPEG image files)",
		"*.png (PNG image files)",
		"*.xbm (X Bitmap image files)"
		};

	imageremap = load Imageremap Imageremap->PATH;
	if(imageremap == nil)
		badload(Imageremap->PATH);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		badload(Bufio->PATH);


	arg->init(argv);
	errdiff := 1;
	while((c := arg->opt()) != 0)
		case c {
		'f' =>
			errdiff = 0;
		'i' =>
			if(!plumbed){
				plumbmsg = load Plumbmsg Plumbmsg->PATH;
				if(plumbmsg != nil && plumbmsg->init(1, "view", 1000) >= 0)
					plumbed = 1;
			}
		}
	argv = arg->argv();
	arg = nil;
	if(argv == nil && !plumbed){
		f := selectfile->filename(ctxt, nil, "View file name", img_patterns, nil);
		if(f == "") {
			#spawn view(nil, nil, "");
			return;
		}
		argv = f :: nil;
	}


	for(;;){
		file: string;
		if(argv != nil){
			file = hd argv;
			argv = tl argv;
			if(file == "-f"){
				errdiff = 0;
				continue;
			}
		}else if(plumbed){
			file = plumbfile();
			if(file == nil)
				break;
			errdiff = 1;	# set this from attributes?
		}else
			break;

		(ims, masks, err) := readimages(file, errdiff);

		if(ims == nil)
			sys->fprint(stderr, "view: can't read %s: %s\n", file, err);
		else
			spawn view(ctxt, ims, masks, file);
	}
}

badload(s: string)
{
	sys->fprint(stderr, "view: can't load %s: %r\n", s);
	raise "fail:load";
}

readimages(file: string, errdiff: int) : (array of ref Image, array of ref Image, string)
{
	im := display.open(file);

	if(im != nil)
		return (array[1] of {im}, array[1] of ref Image, nil);

	fd := bufio->open(file, Sys->OREAD);
	if(fd == nil)
		return (nil, nil, sys->sprint("%r"));

	(mod, err1) := filetype(file, fd);
	if(mod == nil)
		return (nil, nil, err1);

	(ai, err2) := mod->readmulti(fd);
	if(ai == nil)
		return (nil, nil, err2);
	if(err2 != "")
		sys->fprint(stderr, "view: %s: %s\n", file, err2);
	ims := array[len ai] of ref Image;
	masks := array[len ai] of ref Image;
	for(i := 0; i < len ai; i++){
		masks[i] = transparency(ai[i], file);

		# if transparency is enabled, errdiff==1 is probably a mistake,
		# but there's no easy solution.
		(ims[i], err2) = imageremap->remap(ai[i], display, errdiff);
		if(ims[i] == nil)
			return(nil, nil, err2);
	}
	return (ims, masks, nil);
}

DT: con 250;

timer(dt: int, ticks, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		sys->sleep(dt);
		ticks <-= 1;
	}
}

view(ctxt: ref Context, ims, masks: array of ref Image, file: string)
{
	dxy, oxy, xy0: Point;
	file = lastcomponent(file);
	w := wmclient->window(ctxt, "view", Wmclient->Appl);	# Plain?

	menuhit->init(w);
	image := display.newimage(ims[0].r, ims[0].chans, 0, Draw->White);
	if (image == nil) {
		sys->fprint(stderr, "view: can't create image: %r\n");
		return;
	}
	image.draw(image.r, ims[0], masks[0], ims[0].r.min);

	pid := -1;
	ticks := chan of int;
	if(len ims > 1){
		pidc := chan of int;
		spawn timer(DT, ticks, pidc);
		pid = <-pidc;
	}
	imno := 0;
	w.reshape(image.r);
	w.startinput("kbd"::"ptr"::nil);
	w.onscreen(nil);
	redraw(image, w.screen.image);
#	w.image.draw(w.image.r, image, nil, (0,0));

	for(;;) alt{
	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!'){
#			w.image.draw(w.image.r, display.white, nil, (0,0));
#			w.image.draw(w.image.r, image, nil, (0,0));
			redraw(image, w.screen.image);
		}
	p := <-w.ctxt.ptr =>
		if(!w.pointer(*p)){
			if (p.buttons & 2){
				mc := ref Mousectl(w.ctxt.ptr, p.buttons, p.xy, p.msec);
				n := menuhit->menuhit(p.buttons, mc, menu, nil);
				if(n == 0){
				#	plumbmsg->shutdown();
					postnote(1, sys->pctl(0, nil), "kill");
					exit;
				}
			}else if (p.buttons &1){
				oxy = p.xy;
				xy0 = oxy;
				do{
					dxy = p.xy.sub(oxy);
					oxy = p.xy;
					translate(dxy, image, w.screen.image);
					p = <-w.ctxt.ptr;
				} while(p.buttons &1);
				if(p.buttons){
					dxy = xy0.sub(oxy);
					translate(dxy, image, w.screen.image);
				}
				#	w.image.draw(w.image.r, image, nil, p.xy);
			#	w.ctl <-= sys->sprint("!move . -1 %d %d", p.xy.x, p.xy.y);
			}else if(p.buttons &4)
				w.ctl <-= sys->sprint("!size . -1 %d %d", 0, 0);
		}
	<-ticks =>
		;
#		if(masks[imno] != nil)
#			w.image.draw(image.r, image, nil, image.r.min);
#		++imno;
#		if(imno >= len ims)
#			imno = 0;
#		w.image.draw(ims[imno].r,ims[imno], masks[imno], ims[imno].r.min);
	}
}

postnote(t : int, pid : int, note : string) : int
{
	fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (t == 1)
		note += "grp";
	sys->fprint(fd, "%s", note);
	fd = nil;
	return 0;
}

lastcomponent(path: string) : string
{
	for(k:=len path-2; k>=0; k--)
		if(path[k] == '/'){
			path = path[k+1:];
			break;
		}
	return path;
}

plumbfile(): string
{
	if(!plumbed)
		return nil;
	for(;;){
		msg := Msg.recv();
		if(msg == nil){
			sys->print("view: can't read /chan/plumb.view: %r\n");
			return nil;
		}
		if(msg.kind != "text"){
			sys->print("view: can't interpret '%s' kind of message\n", msg.kind);
			continue;
		}
		file := string msg.data;
		if(len file>0 && file[0]!='/' && len msg.dir>0){
			if(msg.dir[len msg.dir-1] == '/')
				file = msg.dir+file;
			else
				file = msg.dir+"/"+file;
		}
		return file;
	}
}

Tab: adt
{
	suf:	string;
	path:	string;
	mod:	RImagefile;
};

GIF, JPG, PIC, PNG, XBM: con iota;

tab := array[] of
{
	GIF => Tab(".gif",	RImagefile->READGIFPATH,	nil),
	JPG => Tab(".jpg",	RImagefile->READJPGPATH,	nil),
	PIC => Tab(".pic",	RImagefile->READPICPATH,	nil),
	XBM => Tab(".xbm",	RImagefile->READXBMPATH,	nil),
	PNG => Tab(".png",	RImagefile->READPNGPATH,	nil),
};

filetype(file: string, fd: ref Iobuf): (RImagefile, string)
{
	for(i:=0; i<len tab; i++){
		n := len tab[i].suf;
		if(len file>n && file[len file-n:]==tab[i].suf)
			return loadmod(i);
	}

	# sniff the header looking for a magic number
	buf := array[20] of byte;
	if(fd.read(buf, len buf) != len buf)
		return (nil, sys->sprint("%r"));
	fd.seek(big 0, 0);
	if(string buf[0:6]=="GIF87a" || string buf[0:6]=="GIF89a")
		return loadmod(GIF);
	if(string buf[0:5] == "TYPE=")
		return loadmod(PIC);
	jpmagic := array[] of {byte 16rFF, byte 16rD8, byte 16rFF, byte 16rE0,
		byte 0, byte 0, byte 'J', byte 'F', byte 'I', byte 'F', byte 0};
	if(eqbytes(buf, jpmagic))
		return loadmod(JPG);
	pngmagic := array[] of {byte 137, byte 80, byte 78, byte 71, byte 13, byte 10, byte 26, byte 10};
	if(eqbytes(buf, pngmagic))
		return loadmod(PNG);
	if(string buf[0:7] == "#define")
		return loadmod(XBM);
	return (nil, "can't recognize file type");
}

eqbytes(buf, magic: array of byte): int
{
	for(i:=0; i<len magic; i++)
		if(magic[i]>byte 0 && buf[i]!=magic[i])
			return 0;
	return i == len magic;
}

loadmod(i: int): (RImagefile, string)
{
	if(tab[i].mod == nil){
		tab[i].mod = load RImagefile tab[i].path;
		if(tab[i].mod == nil)
			sys->fprint(stderr, "view: can't find %s reader: %r\n", tab[i].suf);
		else
			tab[i].mod->init(bufio);
	}
	return (tab[i].mod, nil);
}

transparency(r: ref RImagefile->Rawimage, file: string): ref Image
{
	if(r.transp == 0)
		return nil;
	if(r.nchans != 1){
		sys->fprint(stderr, "view: can't do transparency for multi-channel image %s\n", file);
		return nil;
	}
	i := display.newimage(r.r, display.image.chans, 0, 0);
	if(i == nil){
		sys->fprint(stderr, "view: can't allocate mask for %s: %r\n", file);
		exit;
	}
	pic := r.chans[0];
	npic := len pic;
	mpic := array[npic] of byte;
	index := r.trindex;
	for(j:=0; j<npic; j++)
		if(pic[j] == index)
			mpic[j] = byte 0;
		else
			mpic[j] = byte 16rFF;
	i.writepixels(i.r, mpic);
	return i;
}

redraw(im: ref Image, screen: ref Image)
{
	r: Rect;
	ulrange: Rect;
	if(im == nil)
		return;
	gray := display.color(Draw->Grey);
	ul := screen.r.min;
	ulrange.max = screen.r.max;
	ulrange.min = screen.r.min.sub((im.r.dx(), im.r.dy()));
	
	ul = pclip(ul, ulrange);
	screen.drawop(screen.r, im, nil, im.r.min.sub(ul.sub(screen.r.min)), Draw->S);
	
	if(im.repl)
		return;
	
	r = im.r.addpt(ul.sub(im.r.min));
	screen.border(r, -2, display.black, (0,0));
	r.min = r.min.sub((2,2));
	r.max = r.max.add((2,2));
	
	screen.border(r, -4000, gray, (0,0));
	display.image.flush(0);
}

#
# A draw operation that touches only the area contained in bot but not in top.
# mp and sp get aligned with bot.min.
#
gendrawdiff(dst: ref Image, bot, top: Rect, src : ref Image, sp: Point, mask: ref Image,
mp: Point, op: int)
{
	r: Rect;
	origin, delta: Point;

	if(bot.dx()*bot.dy() == 0)
		return;

	# no points in bot - top 
	if(bot.inrect(top))
		return;

	# bot - top ≡ bot 
	if(top.dx()*top.dy()==0 || bot.Xrect(top)==0){
		dst.gendrawop(bot, src, sp, mask, mp, op);
		return;
	}

	origin = bot.min;
	# split bot into rectangles that don't intersect top */
	# left side */
	if(bot.min.x < top.min.x){
		r = Rect((bot.min.x, bot.min.y), (top.min.x, bot.max.y));
		delta = r.min.sub(origin);
		dst.gendrawop(r, src, sp.add(delta), mask, mp.add(delta), op);
		bot.min.x = top.min.x;
	}

	# right side */
	if(bot.max.x > top.max.x){
		r = Rect((top.max.x, bot.min.y), (bot.max.x, bot.max.y));
		delta = r.min.sub(origin);
		dst.gendrawop(r, src, sp.add(delta), mask, mp.add(delta), op);
		bot.max.x = top.max.x;
	}

	# top */
	if(bot.min.y < top.min.y){
		r = Rect((bot.min.x, bot.min.y), (bot.max.x, top.min.y));
		delta = r.min.sub(origin);
		dst.gendrawop(r, src, sp.add(delta), mask, mp.add(delta), op);
		bot.min.y = top.min.y;
	}

	# bottom */
	if(bot.max.y > top.max.y){
		r = Rect((bot.min.x, top.max.y), (bot.max.x, bot.max.y));
		delta = r.min.sub(origin);
		dst.gendrawop(r, src, sp.add(delta), mask, mp.add(delta), op);
		bot.max.y = top.max.y;
	}
}

drawdiff(dst: ref Image, bot, top: Rect, src, mask: ref Image, p: Point, op: int)
{
	gendrawdiff(dst, bot, top, src, p, mask, p, op);
}

#
# Translate the image in the window by delta.
#

translate(delta: Point, im: ref Image, screen: ref Image)
{
	u: Point;
	r, oor, ulrange: Rect;
	if(im == nil)
		return;
	gray := display.color(Draw->Grey);
	ul := screen.r.min;
	ulrange.max = screen.r.max;
	ulrange.min = screen.r.min.sub((im.r.dx(), im.r.dy()));
	u = pclip(ul.add(delta), ulrange);
	delta = u.sub(ul);
	if(delta.x == 0 && delta.y == 0)
		return;

	#
	# The upper left corner of the image is currently at ul.
	# We want to move it to u.
	#
	oor = Rect((0,0), (im.r.dx(), im.r.dy())).addpt(ul);
	r = oor.addpt(delta);

	screen.drawop(r, screen, nil, ul, Draw->S);
	ul = u;

	# fill in gray where image used to be but isn't. */
	drawdiff(screen, oor.inset(-2), r.inset(-2), gray, nil, (0,0), Draw->S);

	# fill in black border */
	drawdiff(screen, r.inset(-2), r, display.black, nil, (0,0), Draw->S);

	# fill in image where it used to be off the screen. */
	e: int;
	(oor, e) = oor.clip(screen.r);
	if(e)
		drawdiff(screen, r, oor.addpt(delta), im, nil, im.r.min, Draw->S);
	else
		screen.drawop(r, im, nil, im.r.min, Draw->S);
	display.image.flush(1);
}

pclip(p: Point, r: Rect): Point
{
	if(p.x < r.min.x)
		p.x = r.min.x;
	else if(p.x >= r.max.x)
		p.x = r.max.x-1;

	if(p.y < r.min.y)
		p.y = r.min.y;
	else if(p.y >= r.max.y)
		p.y = r.max.y-1;

	return p;
}
