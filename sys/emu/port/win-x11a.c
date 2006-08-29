/*
 * This implementation of the screen functions for X11 uses the
 * portable implementation of the Inferno drawing operations (libmemdraw)
 * to do the work, then has flushmemscreen copy the result to the X11 display.
 * Thus it potentially supports all colour depths but with a possible
 * performance penalty (although it tries to use the X11 shared memory extension
 * to copy the result to the screen, which might reduce the latter).
 *
 *       CraigN 
 */

#define _GNU_SOURCE 1
#include "dat.h"
#include "fns.h"
#include "cursor.h"
#include "keyboard.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

#include "keysym2ucs.h"

#include <sys/ipc.h>
#include <sys/shm.h>
#include <X11/extensions/XShm.h>

/*
 * image channel descriptors - copied from draw.h as it clashes with Linux header files on many things
 */
enum {
	CRed = 0,
	CGreen,
	CBlue,
	CGrey,
	CAlpha,
	CMap,
	CIgnore,
	NChan,
};

#define __DC(type, nbits)	((((type)&15)<<4)|((nbits)&15))
#define CHAN1(a,b)	__DC(a,b)
#define CHAN2(a,b,c,d)	(CHAN1((a),(b))<<8|__DC((c),(d)))
#define CHAN3(a,b,c,d,e,f)	(CHAN2((a),(b),(c),(d))<<8|__DC((e),(f)))
#define CHAN4(a,b,c,d,e,f,g,h)	(CHAN3((a),(b),(c),(d),(e),(f))<<8|__DC((g),(h)))

#define NBITS(c) ((c)&15)
#define TYPE(c) (((c)>>4)&15)

enum {
	GREY1	= CHAN1(CGrey, 1),
	GREY2	= CHAN1(CGrey, 2),
	GREY4	= CHAN1(CGrey, 4),
	GREY8	= CHAN1(CGrey, 8),
	CMAP8	= CHAN1(CMap, 8),
	RGB15	= CHAN4(CIgnore, 1, CRed, 5, CGreen, 5, CBlue, 5),
	RGB16	= CHAN3(CRed, 5, CGreen, 6, CBlue, 5),
	RGB24	= CHAN3(CRed, 8, CGreen, 8, CBlue, 8),
	RGBA32	= CHAN4(CRed, 8, CGreen, 8, CBlue, 8, CAlpha, 8),
	ARGB32	= CHAN4(CAlpha, 8, CRed, 8, CGreen, 8, CBlue, 8),	/* stupid VGAs */
	XRGB32  = CHAN4(CIgnore, 8, CRed, 8, CGreen, 8, CBlue, 8),
};

static int displaydepth;
extern ulong displaychan;

/*
 * alias defs for image types to overcome name conflicts
 */
typedef struct ICursor		ICursor;
typedef struct IPoint		IPoint;
typedef struct IRectangle	IRectangle;
typedef struct CRemapTbl	CRemapTbl;
struct ICursor
{
	int	w;
	int	h;
	int	hotx;
	int	hoty;
	char	*src;
	char	*mask;
};

struct IPoint
{
	int	x;
	int	y;
};

struct IRectangle
{
	IPoint	min;
	IPoint	max;
};

enum
{
	DblTime	= 300		/* double click time in msec */
};

/* screen data .... */
static unsigned char *gscreendata;
static unsigned char *xscreendata;

XColor			map[256];	/* Inferno colormap array */
XColor			mapr[256];	/* Inferno red colormap array */
XColor			mapg[256];	/* Inferno green colormap array */
XColor			mapb[256];	/* Inferno blue colormap array */
XColor			map7[128];	/* Inferno colormap array */
uchar			map7to8[128][2];

/* for copy/paste, lifted from plan9ports via drawterm */
Atom clipboard; 
Atom utf8string;
Atom targets;
Atom text;
Atom compoundtext;

static Colormap		xcmap;		/* Default shared colormap  */
static int 		infernotox11[256]; /* Values for mapping between */
static int 		infernortox11[256]; /* Values for mapping between */
static int 		infernogtox11[256]; /* Values for mapping between */
static int 		infernobtox11[256]; /* Values for mapping between */
static int		triedscreen;
static XModifierKeymap *modmap;
static int		keypermod;
static Drawable		xdrawable;
static void		xexpose(XEvent*);
static void		xmouse(XEvent*);
static void		xkeyboard(XEvent*);
static void		xmapping(XEvent*);
static void		xdestroy(XEvent*);
static void		xselect(XEvent*, Display*);
static void		xproc(void*);
static void		xinitscreen(int, int, ulong, ulong*, int*);
static void		initmap(Window, ulong, ulong*, int*);
static GC		creategc(Drawable);
static void		graphicsgmap(XColor*, int);
static void		graphicscmap(XColor*);
static void		graphicsrgbmap(XColor*, XColor*, XColor*);
static int		xscreendepth;
static	Display*	xdisplay;	/* used holding draw lock */
static	Display*	xkmcon;	/* used only in xproc */
static	Display*	xsnarfcon;	/* used holding clip.lk */
static Visual		*xvis;
static GC		xgc;
static XImage 		*img;
static int              is_shm;
static XShmSegmentInfo	*shminfo;

static int putsnarf, assertsnarf;

extern int	bytesperline(IRectangle, int);
extern void	drawxflush(IRectangle);

/* The documentation for the XSHM extension implies that if the server
   supports XSHM but is not the local machine, the XShm calls will
   return False; but this turns out not to be the case.  Instead, the
   server throws a BadAccess error.  So, we need to catch X errors
   around all of our XSHM calls, sigh.  */
static int shm_got_x_error = False;
static XErrorHandler old_handler = 0;
static XErrorHandler old_io_handler = 0;

static int
shm_ehandler(Display *dpy, XErrorEvent *error)
{
	shm_got_x_error = 1;
	return 0;
}

static void
clean_errhandlers(void)
{
	/* remove X11 error handler(s) */
	if (old_handler)
		XSetErrorHandler(old_handler); 
	old_handler = 0;
	if (old_io_handler)
		XSetErrorHandler(old_io_handler); 
	old_io_handler = 0;
}

uchar*
attachscreen(IRectangle *r, ulong *chan, int *d, int *width, int *softscreen)
{
	ulong c;

	Xsize &= ~0x3;	/* ensure multiple of 4 */

	r->min.x = 0;
	r->min.y = 0;
	r->max.x = Xsize;
	r->max.y = Ysize;

	c = displaychan;
	if(c == 0)
		c = CMAP8;
	
	if(!triedscreen){
		xinitscreen(Xsize, Ysize, c, chan, d);
		/*
		  * moved xproc from here to end since it could cause an expose event and
		  * hence a flushmemscreen before xscreendata is initialized
		  */
	}
	else{
		*chan = displaychan;
		*d = displaydepth;
	}

	*width = (Xsize/4)*(*d/8);
	*softscreen = 1;
	displaychan = *chan;
	displaydepth = *d;

	/* check for X Shared Memory Extension */
	is_shm = XShmQueryExtension(xdisplay);
	
	if (is_shm) {
		shminfo = malloc(sizeof(XShmSegmentInfo));
		if (shminfo == nil) {
			fprint(2, "emu: cannot allocate XShmSegmentInfo\n");
			cleanexit(0);
		}

		/* setup to catch X11 error(s) */
		XSync(xdisplay, 0); 
		shm_got_x_error = 0; 
		if (old_handler != shm_ehandler)
			old_handler = XSetErrorHandler(shm_ehandler);
		if (old_io_handler != shm_ehandler)
			old_io_handler = XSetErrorHandler(shm_ehandler);

		img = XShmCreateImage(xdisplay, xvis, xscreendepth, ZPixmap, 
				      NULL, shminfo, Xsize, Ysize);
		XSync(xdisplay, 0);

		/* did we get an X11 error? if so then try without shm */
		if (shm_got_x_error) {
			is_shm = 0;
			free(shminfo);
			shminfo = NULL;
			clean_errhandlers();
			goto next;
		}
		
		if (!img) {
			fprint(2, "emu: can not allocate virtual screen buffer\n");
			cleanexit(0);
		}
		
		shminfo->shmid = shmget(IPC_PRIVATE, img->bytes_per_line * img->height,
					IPC_CREAT|0777);
		shminfo->shmaddr = img->data = shmat(shminfo->shmid, 0, 0);
		shminfo->readOnly = True;

		if (!XShmAttach(xdisplay, shminfo)) {
			fprint(2, "emu: cannot allocate virtual screen buffer\n");
			cleanexit(0);
		}
		XSync(xdisplay, 0);

		/* Delete the shared segment right now; the segment
		   won't actually go away until both the client and
		   server have deleted it.  The server will delete it
		   as soon as the client disconnects, so we should
		   delete our side early in case of abnormal
		   termination.  (And note that, in the context of
		   xscreensaver, abnormal termination is the rule
		   rather than the exception, so this would leak like
		   a sieve if we didn't do this...)  */
		shmctl(shminfo->shmid, IPC_RMID, 0);

		/* did we get an X11 error? if so then try without shm */
		if (shm_got_x_error) {
			is_shm = 0;
			XDestroyImage(img);
			XSync(xdisplay, 0);
			free(shminfo);
			shminfo = NULL;
			clean_errhandlers();
			goto next;
		}

		gscreendata = malloc(Xsize * Ysize * (displaydepth >> 3));
		if (gscreendata == nil) {
			fprint(2, "emu: cannot allocate screen buffer (%dx%d)\n", Xsize*Ysize);
			cleanexit(0);
		}
		xscreendata = img->data;
		
		clean_errhandlers();
	}
 next:
	if (!is_shm) {
		int depth;

		depth = xscreendepth;
		if(depth == 24)
			depth = 32;

		/* allocate virtual screen */	
		gscreendata = malloc(Xsize * Ysize * (displaydepth >> 3));
		xscreendata = malloc(Xsize * Ysize * (depth >> 3));
		if (!gscreendata || !xscreendata) {
			fprint(2, "emu: can not allocate virtual screen buffer\n");
			return 0;
		}
		img = XCreateImage(xdisplay, xvis, xscreendepth, ZPixmap, 0, 
				   xscreendata, Xsize, Ysize, 8, Xsize * (depth >> 3));
		if (!img) {
			fprint(2, "emu: can not allocate virtual screen buffer\n");
			return 0;
		}
		
	}

	if(!triedscreen){
		triedscreen = 1;
		if(kproc("xproc", xproc, nil, 0) < 0) {
			fprint(2, "emu: win-x11 can't make X proc\n");
			return 0;
		}
	}

	return gscreendata;
}

void
flushmemscreen(IRectangle r)
{
	int x, y, width, height, dx;
	unsigned char *p, *ep, *cp;

	// Clip to screen
	if (r.min.x < 0)
		r.min.x = 0;
	if (r.min.y < 0)
		r.min.y = 0;
	if (r.max.x >= Xsize)
		r.max.x = Xsize - 1;
	if (r.max.y >= Ysize)
                r.max.y = Ysize - 1;

	// is there anything left ...	
	width = r.max.x-r.min.x;
	height = r.max.y-r.min.y;
	if ((width < 1) | (height < 1))
		return;

	// Blit the pixel data ...
	if(displaydepth == 32){
		unsigned int v, w, *dp, *wp, *edp;
	
		dx = Xsize - width;
		dp = (unsigned int *)(gscreendata + (r.min.y * Xsize + r.min.x) * 4);
		wp = (unsigned int *)(xscreendata + (r.min.y * Xsize + r.min.x) * 4);
		edp = (unsigned int *)(gscreendata + (r.max.y * Xsize + r.max.x) * 4);
		while (dp < edp) {
			const unsigned int *lp = dp + width;

			while (dp < lp){
				v = *dp++;
				w = infernortox11[(v>>16)&0xff]<<16|infernogtox11[(v>>8)&0xff]<<8|infernobtox11[(v>>0)&0xff]<<0;
				*wp++ = w;
			}

			dp += dx;
			wp += dx;
		}
	}
	else if(displaydepth == 8){
		if (xscreendepth == 24 || xscreendepth == 32) {
			unsigned int *wp;
	
			dx = Xsize - width;
			p = gscreendata + r.min.y * Xsize + r.min.x;
			wp = (unsigned int *)(xscreendata + (r.min.y * Xsize + r.min.x) * 4);
			ep = gscreendata + r.max.y * Xsize + r.max.x;
			while (p < ep) {
				const unsigned char *lp = p + width;

				while (p < lp) 
					*wp++ = infernotox11[*p++];

				p += dx;
				wp += dx;
			}

		} else if (xscreendepth == 24) {
			int v;

			dx = Xsize - width;
			p = gscreendata + r.min.y * Xsize + r.min.x;
			cp = xscreendata + (r.min.y * Xsize + r.min.x) * 3;
			ep = gscreendata + r.max.y * Xsize + r.max.x;
			while (p < ep) {
				const unsigned char *lp = p + width;

				while (p < lp){
					v = infernotox11[*p++];
					cp[0] = (v>>16)&0xff;
					cp[1] = (v>>8)&0xff;
					cp[2] = (v>>0)&0xff;
					cp += 3;
				}

				p += dx;
				cp += 3*dx;
			}

		} else if (xscreendepth == 16) {
			unsigned short *sp;
	
			dx = Xsize - width;
			p = gscreendata + r.min.y * Xsize + r.min.x;
			sp = (unsigned short *)(xscreendata + (r.min.y * Xsize + r.min.x) * 2);
			ep = gscreendata + r.max.y * Xsize + r.max.x;
			while (p < ep) {
				const unsigned char *lp = p + width;

				while (p < lp) 
					*sp++ = infernotox11[*p++];

				p += dx;
				sp += dx;
			}

		} else if (xscreendepth == 8) {

                		dx = Xsize - width;
                		p = gscreendata + r.min.y * Xsize + r.min.x;
                		cp = xscreendata + r.min.y * Xsize + r.min.x;
                		ep = gscreendata + r.max.y * Xsize + r.max.x;
                		while (p < ep) {
                        		const unsigned char *lp = p + width;

                        		while (p < lp)
                                		*cp++ = infernotox11[*p++];

                        		p += dx;
                        		cp += dx;
                		}

		} else {
			for (y = r.min.y; y < r.max.y; y++) {
				x = r.min.x;
				p = gscreendata + y * Xsize + x;
				while (x < r.max.x)
					XPutPixel(img, x++, y, infernotox11[*p++]);
			}
		}
	}
	else{
		fprint(2, "emu: bad display depth %d\n", displaydepth);
		cleanexit(0);
	}

	/* Display image on X11 */
	if (is_shm)
		XShmPutImage(xdisplay, xdrawable, xgc, img, r.min.x, r.min.y, r.min.x, r.min.y, width, height, 0);
	else
		XPutImage(xdisplay, xdrawable, xgc, img, r.min.x, r.min.y, r.min.x, r.min.y, width, height);
	XSync(xdisplay, 0);
}

static int
revbyte(int b)
{
	int r;

	r = 0;
	r |= (b&0x01) << 7;
	r |= (b&0x02) << 5;
	r |= (b&0x04) << 3;
	r |= (b&0x08) << 1;
	r |= (b&0x10) >> 1;
	r |= (b&0x20) >> 3;
	r |= (b&0x40) >> 5;
	r |= (b&0x80) >> 7;
	return r;
}

static void
gotcursor(ICursor c)
{
	Cursor xc;
	XColor fg, bg;
	Pixmap xsrc, xmask;
	static Cursor xcursor;

	if(c.src == nil){
		if(xcursor != 0) {
			XFreeCursor(xdisplay, xcursor);
			xcursor = 0;
		}
		XUndefineCursor(xdisplay, xdrawable);
		XFlush(xdisplay);
		return;
	}
	xsrc = XCreateBitmapFromData(xdisplay, xdrawable, c.src, c.w, c.h);
	xmask = XCreateBitmapFromData(xdisplay, xdrawable, c.mask, c.w, c.h);

	fg = map[0];	/* was 255 */
	bg = map[255];	/* was 0 */
	fg.pixel = infernotox11[0];	/* was 255 */
	bg.pixel = infernotox11[255];	/* was 0 */
	xc = XCreatePixmapCursor(xdisplay, xsrc, xmask, &fg, &bg, -c.hotx, -c.hoty);
	if(xc != 0) {
		XDefineCursor(xdisplay, xdrawable, xc);
		if(xcursor != 0)
			XFreeCursor(xdisplay, xcursor);
		xcursor = xc;
	}
	XFreePixmap(xdisplay, xsrc);
	XFreePixmap(xdisplay, xmask);
	XFlush(xdisplay);
	free(c.src);
}

void
setcursor(IPoint p)
{
	XWarpPointer(xdisplay, None, xdrawable, 0, 0, 0, 0, p.x, p.y);
	XFlush(xdisplay);
}

void
setpointer(int x, int y)
{
	XWarpPointer(xdisplay, None, xdrawable, 0, 0, 0, 0, x, y);
	XFlush(xdisplay);
}

void
drawcursor(Drawcursor* c)
{
	ICursor ic;
	IRectangle ir;
	uchar *bs, *bc;
	int i, j;
	int h = 0, bpl = 0;
	char *src, *mask, *csrc, *cmask;

	/* Set the default system cursor */
	src = nil;
	mask = nil;
	if(c->data != nil){
		h = (c->maxy-c->miny)/2;
		ir.min.x = c->minx;
		ir.min.y = c->miny;
		ir.max.x = c->maxx;
		ir.max.y = c->maxy;
		/* passing IRectangle to Rectangle is safe */
		bpl = bytesperline(ir, 1);

		i = h*bpl;
		src = malloc(2*i);
		if(src == nil)
			return;
		mask = src + i;

		csrc = src;
		cmask = mask;
		bc = c->data;
		bs = c->data + h*bpl;
		for(i = 0; i < h; i++){
			for(j = 0; j < bpl; j++) {
				*csrc++ = revbyte(bs[j]);
				*cmask++ = revbyte(bs[j] | bc[j]);
			}
			bs += bpl;
			bc += bpl;
		}
	}
	ic.w = 8*bpl;
	ic.h = h;
	ic.hotx = c->hotx;
	ic.hoty = c->hoty;
	ic.src = src;
	ic.mask = mask;

	gotcursor(ic);
}

static void
xproc(void *arg)
{
	ulong mask;
	XEvent event;

	closepgrp(up->env->pgrp);
	closefgrp(up->env->fgrp);
	closeegrp(up->env->egrp);
	closesigs(up->env->sigs);

	mask = 	KeyPressMask|
		ButtonPressMask|
		ButtonReleaseMask|
		PointerMotionMask|
		Button1MotionMask|
		Button2MotionMask|
		Button3MotionMask|
		Button4MotionMask|
		Button5MotionMask|
		ExposureMask|
		StructureNotifyMask;

	XSelectInput(xkmcon, xdrawable, mask);		
	for(;;) {
		//XWindowEvent(xkmcon, xdrawable, mask, &event);
		XNextEvent(xkmcon, &event);
		xselect(&event, xkmcon);
		xkeyboard(&event);
		xmouse(&event);
		xexpose(&event);
		xmapping(&event);
		xdestroy(&event);
	}
}

static void
xinitscreen(int xsize, int ysize, ulong c, ulong *chan, int *d)
{
	char *argv[2];
	char *disp_val;
	Window rootwin;
	XWMHints hints;
	Screen *screen;
	int rootscreennum;
	XTextProperty name;
	XClassHint classhints;
	XSizeHints normalhints;
	XSetWindowAttributes attrs;
 
	xdrawable = 0;

	xdisplay = XOpenDisplay(NULL);
	if(xdisplay == 0){
		disp_val = getenv("DISPLAY");
		if(disp_val == 0)
			disp_val = "not set";
		fprint(2, "emu: win-x11 open %r, DISPLAY is %s\n", disp_val);
		cleanexit(0);
	}

	rootscreennum = DefaultScreen(xdisplay);
	rootwin = DefaultRootWindow(xdisplay);
	xscreendepth = DefaultDepth(xdisplay, rootscreennum);
	xvis = DefaultVisual(xdisplay, rootscreennum);
	screen = DefaultScreenOfDisplay(xdisplay);
	xcmap = DefaultColormapOfScreen(screen);

	*chan = CMAP8;
	*d = 8;

	if (xvis->class != StaticColor) {
		if(TYPE(c) == CGrey)
			graphicsgmap(map, NBITS(c));
		else{
			graphicscmap(map);
			graphicsrgbmap(mapr, mapg, mapb);
		}
		initmap(rootwin, c, chan, d);
	}

	if ((modmap = XGetModifierMapping(xdisplay)) != 0)
		keypermod = modmap->max_keypermod;

	attrs.colormap = xcmap;
	attrs.background_pixel = 0;
	attrs.border_pixel = 0;
	/* attrs.override_redirect = 1;*/ /* WM leave me alone! |CWOverrideRedirect */
	xdrawable = XCreateWindow(xdisplay, rootwin, 0, 0, xsize, ysize, 0, xscreendepth, 
				  InputOutput, xvis, CWBackPixel|CWBorderPixel|CWColormap, &attrs);

	/*
	 * set up property as required by ICCCM
	 */
	name.value = "inferno";
	name.encoding = XA_STRING;
	name.format = 8;
	name.nitems = strlen(name.value);
	normalhints.flags = USSize|PMaxSize;
	normalhints.max_width = normalhints.width = xsize;
	normalhints.max_height = normalhints.height = ysize;
	hints.flags = InputHint|StateHint;
	hints.input = 1;
	hints.initial_state = NormalState;
	classhints.res_name = "inferno";
	classhints.res_class = "Inferno";
	argv[0] = "inferno";
	argv[1] = nil;
	XSetWMProperties(xdisplay, xdrawable,
		&name,			/* XA_WM_NAME property for ICCCM */
		&name,			/* XA_WM_ICON_NAME */
		argv,			/* XA_WM_COMMAND */
		1,			/* argc */
		&normalhints,		/* XA_WM_NORMAL_HINTS */
		&hints,			/* XA_WM_HINTS */
		&classhints);		/* XA_WM_CLASS */

	XMapWindow(xdisplay, xdrawable);
	XFlush(xdisplay);

	xgc = creategc(xdrawable);

	xkmcon = XOpenDisplay(NULL);
	if(xkmcon == 0){
		disp_val = getenv("DISPLAY");
		if(disp_val == 0)
			disp_val = "not set";
		fprint(2, "emu: win-x11 open %r, DISPLAY is %s\n", disp_val);
		cleanexit(0);
	}
	xsnarfcon = XOpenDisplay(NULL);
	if(xsnarfcon == 0){
		disp_val = getenv("DISPLAY");
		if(disp_val == 0)
			disp_val = "not set";
		iprint("emu: win-x11 open %r, DISPLAY is %s\n", disp_val);
		cleanexit(0);
	}

	clipboard = XInternAtom(xkmcon, "CLIPBOARD", False);
	utf8string = XInternAtom(xkmcon, "UTF8_STRING", False);
	targets = XInternAtom(xkmcon, "TARGETS", False);
	text = XInternAtom(xkmcon, "TEXT", False);
	compoundtext = XInternAtom(xkmcon, "COMPOUND_TEXT", False);

}

static void
graphicsgmap(XColor *map, int d)
{
	int i, j, s, m, p;

	s = 8-d;
	m = 1;
	while(--d >= 0)
		m *= 2;
	m = 255/(m-1);
	for(i=0; i < 256; i++){
		j = (i>>s)*m;
		p = 255-i;
		map[p].red = map[p].green = map[p].blue = (255-j)*0x0101;
		map[p].pixel = p;
		map[p].flags = DoRed|DoGreen|DoBlue;
	}
}

static void
graphicscmap(XColor *map)
{
	int r, g, b, cr, cg, cb, v, num, den, idx, v7, idx7;

	for(r=0; r!=4; r++) {
		for(g = 0; g != 4; g++) {
			for(b = 0; b!=4; b++) {
				for(v = 0; v!=4; v++) {
					den=r;
					if(g > den)
						den=g;
					if(b > den)
						den=b;
					/* divide check -- pick grey shades */
					if(den==0)
						cr=cg=cb=v*17;
					else {
						num=17*(4*den+v);
						cr=r*num/den;
						cg=g*num/den;
						cb=b*num/den;
					}
					idx = r*64 + v*16 + ((g*4 + b + v - r) & 15);
					/* was idx = 255 - idx; */
					map[idx].red = cr*0x0101;
					map[idx].green = cg*0x0101;
					map[idx].blue = cb*0x0101;
					map[idx].pixel = idx;
					map[idx].flags = DoRed|DoGreen|DoBlue;

					v7 = v >> 1;
					idx7 = r*32 + v7*16 + g*4 + b;
					if((v & 1) == v7){
						map7to8[idx7][0] = idx;
						if(den == 0) { 		/* divide check -- pick grey shades */
							cr = ((255.0/7.0)*v7)+0.5;
							cg = cr;
							cb = cr;
						}
						else {
							num=17*15*(4*den+v7*2)/14;
							cr=r*num/den;
							cg=g*num/den;
							cb=b*num/den;
						}
						map7[idx7].red = cr*0x0101;
						map7[idx7].green = cg*0x0101;
						map7[idx7].blue = cb*0x0101;
						map7[idx7].pixel = idx7;
						map7[idx7].flags = DoRed|DoGreen|DoBlue;
					}
					else
						map7to8[idx7][1] = idx;
				}
			}
		}
	}
}

static void
graphicsrgbmap(XColor *mapr, XColor *mapg, XColor *mapb)
{
	int i;

	memset(mapr, 0, 256*sizeof(XColor));
	memset(mapg, 0, 256*sizeof(XColor));
	memset(mapb, 0, 256*sizeof(XColor));
	for(i=0; i < 256; i++){
		mapr[i].red = mapg[i].green = mapb[i].blue = i*0x0101;
		mapr[i].pixel = mapg[i].pixel = mapb[i].pixel = i;
		mapr[i].flags = mapg[i].flags = mapb[i].flags = DoRed|DoGreen|DoBlue;
	}
}

/*
 * Initialize and install the Inferno colormap as a private colormap for this
 * application.  Inferno gets the best colors here when it has the cursor focus.
 */  
static void 
initmap(Window w, ulong cc, ulong *chan, int *d)
{
	XColor c;
	int i;

	if(xscreendepth <= 1)
		return;

	if(xvis->class == TrueColor || xvis->class == DirectColor) {
		for(i = 0; i < 256; i++) {
			c = map[i];
			/* find out index into colormap for our RGB */
			if(!XAllocColor(xdisplay, xcmap, &c)) {
				fprint(2, "emu: win-x11 can't alloc color\n");
				cleanexit(0);
			}
			infernotox11[map[i].pixel] = c.pixel;
			if(xscreendepth >= 24){
				c = mapr[i];
				XAllocColor(xdisplay, xcmap, &c);
				infernortox11[i] = (c.pixel>>16)&0xff;
				c = mapg[i];
				XAllocColor(xdisplay, xcmap, &c);
				infernogtox11[i] = (c.pixel>>8)&0xff;
				c = mapb[i];
				XAllocColor(xdisplay, xcmap, &c);
				infernobtox11[i] = (c.pixel>>0)&0xff;
			}
		}
		if(TYPE(cc) != CGrey && cc != CMAP8 && xscreendepth >= 24){
			*chan = XRGB32;
			*d = 32;
		}
	}
	else if(xvis->class == PseudoColor) {
		if(xtblbit == 0){
			xcmap = XCreateColormap(xdisplay, w, xvis, AllocAll); 
			XStoreColors(xdisplay, xcmap, map, 256);
			for(i = 0; i < 256; i++)
				infernotox11[i] = i;
		} else {
			for(i = 0; i < 128; i++) {
				c = map7[i];
				if(!XAllocColor(xdisplay, xcmap, &c)) {
					fprint(2, "emu: win-x11 can't alloc colors in default map, don't use -7\n");
					cleanexit(0);
				}
				infernotox11[map7to8[i][0]] = c.pixel;
				infernotox11[map7to8[i][1]] = c.pixel;
			}
		}
	}
	else {
		xtblbit = 0;
		fprint(2, "emu: win-x11 unsupported visual class %d\n", xvis->class);
	}
	return;
}

static void
xmapping(XEvent *e)
{
	XMappingEvent *xe;

	if(e->type != MappingNotify)
		return;
	xe = (XMappingEvent*)e;
	if(modmap)
		XFreeModifiermap(modmap);
	modmap = XGetModifierMapping(xe->display);
	if(modmap)
		keypermod = modmap->max_keypermod;
}

static void
xdestroy(XEvent *e)
{
	XDestroyWindowEvent *xe;
	if(e->type != DestroyNotify)
		return;
	xe = (XDestroyWindowEvent*)e;
	if(xe->window == xdrawable)
		cleanexit(0);
}

/*
 * Disable generation of GraphicsExpose/NoExpose events in the GC.
 */
static GC
creategc(Drawable d)
{
	XGCValues gcv;

	gcv.function = GXcopy;
	gcv.graphics_exposures = False;
	return XCreateGC(xdisplay, d, GCFunction|GCGraphicsExposures, &gcv);
}

static void
xexpose(XEvent *e)
{
	IRectangle r;
	XExposeEvent *xe;

	if(e->type != Expose)
		return;
	xe = (XExposeEvent*)e;
	r.min.x = xe->x;
	r.min.y = xe->y;
	r.max.x = xe->x + xe->width;
	r.max.y = xe->y + xe->height;
	drawxflush(r);
}

static void
xkeyboard(XEvent *e)
{
	int ind;
	KeySym k;
	unsigned int md;

	if(e->type == KeyPress && gkscanq != nil) {
		uchar ch = (KeyCode)e->xkey.keycode;
		if(e->xany.type == KeyRelease)
			ch |= 0x80;
		qproduce(gkscanq, &ch, 1);
		return;
	}

        /*
         * I tried using XtGetActionKeysym, but it didn't seem to
         * do case conversion properly
         * (at least, with Xterminal servers and R4 intrinsics)
         */
	if(e->xany.type != KeyPress)
		return;

	md = e->xkey.state;
	ind = 0;
	if(md & ShiftMask)
		ind = 1;
	if(0){
		k = XKeycodeToKeysym(e->xany.display, (KeyCode)e->xkey.keycode, ind);

		/* May have to try unshifted version */
		if(k == NoSymbol && ind == 1)
			k = XKeycodeToKeysym(e->xany.display, (KeyCode)e->xkey.keycode, 0);
	}else
		XLookupString((XKeyEvent*)e, NULL, 0, &k, NULL);

	if(k == XK_Multi_key || k == NoSymbol)
		return;
	if(k&0xFF00){
		switch(k){
		case XK_BackSpace:
		case XK_Tab:
		case XK_Escape:
		case XK_Delete:
		case XK_KP_0:
		case XK_KP_1:
		case XK_KP_2:
		case XK_KP_3:
		case XK_KP_4:
		case XK_KP_5:
		case XK_KP_6:
		case XK_KP_7:
		case XK_KP_8:
		case XK_KP_9:
		case XK_KP_Divide:
		case XK_KP_Multiply:
		case XK_KP_Subtract:
		case XK_KP_Add:
		case XK_KP_Decimal:
			k &= 0x7F;
			break;
		case XK_Linefeed:
			k = '\r';
			break;
		case XK_KP_Space:
			k = ' ';
			break;
//		case XK_Home:
//		case XK_KP_Home:
//			k = Khome;
//			break;
		case XK_Left:
		case XK_KP_Left:
			k = Left;
			break;
		case XK_Up:
		case XK_KP_Up:
			k = Up;
			break;
		case XK_Down:
		case XK_KP_Down:
			k = Down;
			break;
		case XK_Right:
		case XK_KP_Right:
			k = Right;
			break;
//		case XK_Page_Down:
//		case XK_KP_Page_Down:
//			k = Kpgdown;
//			break;
		case XK_End:
		case XK_KP_End:
			k = End;
			break;
//		case XK_Page_Up:	
//		case XK_KP_Page_Up:
//			k = Kpgup;
//			break;
//		case XK_Insert:
//		case XK_KP_Insert:
//			k = Kins;
//			break;
		case XK_KP_Enter:
		case XK_Return:
			k = '\n';
			break;
		case XK_Alt_L:
		case XK_Alt_R:
			k = Latin;
			break;
		case XK_Shift_L:
		case XK_Shift_R:
		case XK_Control_L:
		case XK_Control_R:
		case XK_Caps_Lock:
		case XK_Shift_Lock:

		case XK_Meta_L:
		case XK_Meta_R:
		case XK_Super_L:
		case XK_Super_R:
		case XK_Hyper_L:
		case XK_Hyper_R:
			return;
		default:                /* not ISO-1 or tty control */
 			if(k>0xff){
				k = keysym2ucs(k); /* supplied by X */
				if(k == -1)
					return;
			}
			break;
		}
	}

	/* Compensate for servers that call a minus a hyphen */
	if(k == XK_hyphen)
		k = XK_minus;
	/* Do control mapping ourselves if translator doesn't */
	if(md & ControlMask)
		k &= 0x9f;
	if(0){
		if(k == '\t' && ind)
			k = BackTab;

		if(md & Mod1Mask)
			k = APP|(k&0xff);
	}
	if(k == NoSymbol)
		return;

        gkbdputc(gkbdq, k);
}

static void
xmouse(XEvent *e)
{
	int s, dbl;
	XButtonEvent *be;
	XMotionEvent *me;
	XEvent motion;
	int x, y, b;
	static ulong lastb, lastt;

	if(putsnarf != assertsnarf){
		assertsnarf = putsnarf;
		XSetSelectionOwner(xkmcon, XA_PRIMARY, xdrawable, CurrentTime);
		if(clipboard != None)
			XSetSelectionOwner(xkmcon, clipboard, xdrawable, CurrentTime);
		XFlush(xkmcon);
	}

	dbl = 0;
	switch(e->type){
	case ButtonPress:
		be = (XButtonEvent *)e;
		/* 
		 * Fake message, just sent to make us announce snarf.
		 * Apparently state and button are 16 and 8 bits on
		 * the wire, since they are truncated by the time they
		 * get to us.
		 */
		if(be->send_event
		&& (~be->state&0xFFFF)==0
		&& (~be->button&0xFF)==0)
			return;
		x = be->x;
		y = be->y;
		s = be->state;
		if(be->button == lastb && be->time - lastt < DblTime)
			dbl = 1;
		lastb = be->button;
		lastt = be->time;
		switch(be->button){
		case 1:
			s |= Button1Mask;
			break;
		case 2:
			s |= Button2Mask;
			break;
		case 3:
			s |= Button3Mask;
			break;
		case 4:
			s |= Button4Mask;
			break;
		case 5:
			s |= Button5Mask;
			break;
		}
		break;
	case ButtonRelease:
		be = (XButtonEvent *)e;
		x = be->x;
		y = be->y;
		s = be->state;
		switch(be->button){
		case 1:
			s &= ~Button1Mask;
			break;
		case 2:
			s &= ~Button2Mask;
			break;
		case 3:
			s &= ~Button3Mask;
			break;
		case 4:
			s &= ~Button4Mask;
			break;
		case 5:
			s &= ~Button5Mask;
			break;
		}
		break;
	case MotionNotify:
		me = (XMotionEvent *) e;

		/* remove excess MotionNotify events from queue and keep last one */
		while(XCheckTypedWindowEvent(xkmcon, xdrawable, MotionNotify, &motion) == True)
			me = (XMotionEvent *) &motion;

		s = me->state;
		x = me->x;
		y = me->y;
		break;
	default:
		return;
	}

	b = 0;
	if(s & Button1Mask)
		b |= 1;
	if(s & Button2Mask)
		b |= 2;
	if(s & Button3Mask)
		b |= 4;
	if(s & Button4Mask)
		b |= 8;
	if(s & Button5Mask)
		b |= 16;
	if(dbl)
		b |= 1<<8;

	mousetrack(b, x, y, 0);
}

#include "x11-keysym2ucs.c"

/*
 * Cut and paste.  Just couldn't stand to make this simple...
 */

enum{
	SnarfSize=	100*1024
};

typedef struct Clip Clip;
struct Clip
{
	char buf[SnarfSize];
	QLock lk;
};
Clip clip;

#undef long	/* sic */
#undef ulong

static char*
_xgetsnarf(Display *xd)
{
	uchar *data, *xdata;
	Atom clipboard, type, prop;
	unsigned long len, lastlen, dummy;
	int fmt, i;
	Window w;

	qlock(&clip.lk);
	/*
	 * Have we snarfed recently and the X server hasn't caught up?
	 */
	if(putsnarf != assertsnarf)
		goto mine;

	/*
	 * Is there a primary selection (highlighted text in an xterm)?
	 */
	clipboard = XA_PRIMARY;
	w = XGetSelectionOwner(xd, XA_PRIMARY);
	if(w == xdrawable){
	mine:
		data = (uchar*)strdup(clip.buf);
		goto out;
	}

	/*
	 * If not, is there a clipboard selection?
	 */
	if(w == None && clipboard != None){
		clipboard = clipboard;
		w = XGetSelectionOwner(xd, clipboard);
		if(w == xdrawable)
			goto mine;
	}

	/*
	 * If not, give up.
	 */
	if(w == None){
		data = nil;
		goto out;
	}
		
	/*
	 * We should be waiting for SelectionNotify here, but it might never
	 * come, and we have no way to time out.  Instead, we will clear
	 * local property #1, request our buddy to fill it in for us, and poll
	 * until he's done or we get tired of waiting.
	 *
	 * We should try to go for utf8string instead of XA_STRING,
	 * but that would add to the polling.
	 */
	prop = 1;
	XChangeProperty(xd, xdrawable, prop, XA_STRING, 8, PropModeReplace, (uchar*)"", 0);
	XConvertSelection(xd, clipboard, XA_STRING, prop, xdrawable, CurrentTime);
	XFlush(xd);
	lastlen = 0;
	for(i=0; i<10 || (lastlen!=0 && i<30); i++){
		osmillisleep(100);
		XGetWindowProperty(xd, xdrawable, prop, 0, 0, 0, AnyPropertyType,
			&type, &fmt, &dummy, &len, &data);
		if(lastlen == len && len > 0)
			break;
		lastlen = len;
	}
	if(i == 10){
		data = nil;
		goto out;
	}
	/* get the property */
	data = nil;
	XGetWindowProperty(xd, xdrawable, prop, 0, SnarfSize/sizeof(unsigned long), 0, 
		AnyPropertyType, &type, &fmt, &len, &dummy, &xdata);
	if((type != XA_STRING && type != utf8string) || len == 0){
		if(xdata)
			XFree(xdata);
		data = nil;
	}else{
		if(xdata){
			data = (uchar*)strdup((char*)xdata);
			XFree(xdata);
		}else
			data = nil;
	}
out:
	qunlock(&clip.lk);
	return (char*)data;
}

static void
_xputsnarf(Display *xd, char *data)
{
	XButtonEvent e;

	if(strlen(data) >= SnarfSize)
		return;
	qlock(&clip.lk);
	strcpy(clip.buf, data);

	/* leave note for mouse proc to assert selection ownership */
	putsnarf++;

	/* send mouse a fake event so snarf is announced */
	memset(&e, 0, sizeof e);
	e.type = ButtonPress;
	e.window = xdrawable;
	e.state = ~0;
	e.button = ~0;
	XSendEvent(xd, xdrawable, True, ButtonPressMask, (XEvent*)&e);
	XFlush(xd);
	qunlock(&clip.lk);
}

static void
xselect(XEvent *e, Display *xd)
{
	char *name;
	XEvent r;
	XSelectionRequestEvent *xe;
	Atom a[4];

	if(e->xany.type != SelectionRequest)
		return;

	memset(&r, 0, sizeof r);
	xe = (XSelectionRequestEvent*)e;
if(0) iprint("xselect target=%d requestor=%d property=%d selection=%d\n",
	xe->target, xe->requestor, xe->property, xe->selection);
	r.xselection.property = xe->property;
	if(xe->target == targets){
		a[0] = XA_STRING;
		a[1] = utf8string;
		a[2] = text;
		a[3] = compoundtext;

		XChangeProperty(xd, xe->requestor, xe->property, xe->target,
			8, PropModeReplace, (uchar*)a, sizeof a);
	}else if(xe->target == XA_STRING || xe->target == utf8string || xe->target == text || xe->target == compoundtext){
		/* if the target is STRING we're supposed to reply with Latin1 XXX */
		qlock(&clip.lk);
		XChangeProperty(xd, xe->requestor, xe->property, xe->target,
			8, PropModeReplace, (uchar*)clip.buf, strlen(clip.buf));
		qunlock(&clip.lk);
	}else{
		iprint("get %d\n", xe->target);
		name = XGetAtomName(xd, xe->target);
		if(name == nil)
			iprint("XGetAtomName failed\n");
		else if(strcmp(name, "TIMESTAMP") != 0)
			iprint("%s: cannot handle selection request for '%s' (%d)\n", argv0, name, (int)xe->target);
		r.xselection.property = None;
	}

	r.xselection.display = xe->display;
	/* r.xselection.property filled above */
	r.xselection.target = xe->target;
	r.xselection.type = SelectionNotify;
	r.xselection.requestor = xe->requestor;
	r.xselection.time = xe->time;
	r.xselection.send_event = True;
	r.xselection.selection = xe->selection;
	XSendEvent(xd, xe->requestor, False, 0, &r);
	XFlush(xd);
}

char*
clipread(void)
{
	return _xgetsnarf(xsnarfcon);
}

int
clipwrite(char *buf)
{
	_xputsnarf(xsnarfcon, buf);
	return 0;
}
