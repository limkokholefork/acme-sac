implement IInstrument;

include "sys.m";
	sys:Sys;
include "math.m";
	math: Math;
	sin, cos, Pi, pow, sqrt: import math;
include "instrument.m";
	Context, Source, Sample, Control, BLOCK, CFREQ, CRADIUS,
	CKEYON, CKEYOFF, CATTACK, CDECAY, CSUSTAIN,
	CRELEASE, CHIGH, CLOW, CPOLE,CZERO: import Instrument;
	instrument: Instrument;
	getInstrument: import instrument;
include "exprs.m";
	exprs: Exprs;
	Expr: import exprs;

channels: int;
samplerate: real;
config: string;
lfoconfig := "lfo 0.27 -0.8 0.8";

init(ctxt: Context)
{
	sys = load Sys Sys->PATH;
	instrument = load Instrument Instrument->PATH;
	math = load Math Math->PATH;
	exprs = load Exprs Exprs->PATH;
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
	e := Expr.parse(ctxt.config :: nil);
	if(e != nil && e.islist()){
		args := e.args();
		if(args != nil){
			config = (hd args).text();
			args = tl args;
		}
		if(args != nil){
			lfoconfig = (hd args).text();
			args = tl args;
		}
	}
}

# lfo's don't need a high sampling rate and only need one channel.
# parameters change only one blocking factor which limits the
# sampling rate.
synth(nil: Source, c: Sample, ctl: Control)
{
	lfo := getInstrument(nil, lfoconfig);
	filter := getInstrument(nil, config);
	wrc := chan of array of real;
	coef := array[BLOCK*channels] of real;
	
	for(;;) alt {
	(a, rc) := <-c =>
		lfo.c <-= (coef[:len a/channels], wrc);
		filter.ctl <-= (CPOLE, <-wrc);
		filter.c <-= (a, wrc);
		rc <-= <-wrc;
	(m, n) := <-ctl =>
		;
	}
}
