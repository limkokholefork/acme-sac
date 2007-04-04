implement IInstrument;

include "math.m";
	math: Math;
	sin, cos, Pi, pow, sqrt: import math;
include "instrument.m";
	instrument: Instrument;
	Context, Source, Sample, Control, Inst,
	BLOCK, CFREQ, CRADIUS, CATTACK, CDECAY, CSUSTAIN, CRELEASE,
	CKEYON, CKEYOFF, CDELAY, CMIX, CHIGH, CLOW, CVOICE: import Instrument;
	getInstrument: import instrument;
include "exprs.m";
	expr: Exprs;
	Expr: import expr;
	
channels: int;
samplerate: real;
fmconfig := "fm";
args : list of ref Expr;

init(ctxt: Context)
{
	math = load Math Math->PATH;
	expr = load Exprs Exprs->PATH;
	instrument = load Instrument Instrument->PATH;
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
	e := Expr.parse(ctxt.config :: nil);
	if(e != nil && e.islist()){
		args = e.args();
		fmconfig = (hd args).text();
		args = tl args;
	}
}

synth(nil: Source, c: Sample, ctl: Control)
{
	inst := array[8] of ref Inst;
	voice := 0;
	mix := getInstrument(inst, "mixer 0.8");
	wrc := chan of array of real;
	opt := array[len args] of ref Inst;
	i := 0;
	for( l := args; l != nil; l = tl l)
		opt[i++] = getInstrument(nil, (hd l).text());


	for(;;) alt {
	(a, rc ) := <-c =>
		mix.c <-= (a, wrc);
		for(i = 0; i < len opt; i++)
			opt[i].c <-= (<-wrc, wrc);
		rc <-= <-wrc;
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			inst[voice].ctl <-= (m, n);
		CKEYOFF =>
			inst[voice].ctl <-= (m, n);
		CVOICE =>
			voice = int n[0];
			# two note polyphony for each voice using 'fm' as the generator
			if(inst[voice] == nil)
				inst[voice] = getInstrument(array[2] of {* => getInstrument(nil, fmconfig)}, "poly");
		}
	}
}
