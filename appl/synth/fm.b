implement IInstrument;

include "sys.m";
include "draw.m";
include "math.m";
	math: Math;
	sin, cos, Pi, pow, sqrt: import math;
include "instrument.m";
	instrument: Instrument;
	Context, Source, Sample, Control, Inst,
	BLOCK, CFREQ, CRADIUS, CATTACK, CDECAY, CSUSTAIN, CRELEASE,
	CKEYON, CKEYOFF: import Instrument;
	getInstrument: import instrument;
include "exprs.m";
	exprs: Exprs;
	Expr: import exprs;

channels: int;
samplerate: real;
config := "waveloop";
adsr := "{adsr 0.01 0.11 0.3 0.001}";

init(ctxt: Context)
{
	math = load Math Math->PATH;
	instrument = load Instrument Instrument->PATH;
	exprs = load Exprs Exprs->PATH;
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
	e :=Expr.parse(ctxt.config :: nil);
	if(e != nil && e.islist()){
		args := e.args();
		config = (hd args).text();
		args = tl args;
		if(args != nil)
			adsr = (hd args).text();
	}
}

synth(nil: Source, c: Sample, ctl: Control)
{
	ratios := array[] of {1.0, 0.5, 2.0};
	waves := array[len ratios] of { * => array[1] of {getInstrument(nil, config)} };
	vibrato := getInstrument(nil, "waveloop");
	depth := 0.2;
	vibrato.ctl <-= (CFREQ, array[] of {3.0});
	env := array[len ratios] of ref Inst;
	for(i := 0; i < len ratios; i++){
		env[i] = getInstrument(waves[i], adsr);
	}

	mix := getInstrument(env, "mixer");
	b := array[BLOCK*channels] of real;
	wrc := chan of array of real;
	for(;;) alt{
	(a, rc) := <-c =>
		mix.c <-= (a, wrc);
		a =<- wrc;
		vibrato.c <-= (b[:len a], wrc);
		x :=<- wrc;
		for(i = 0; i < len a; i++)
			a[i] *= (1.0 + x[i] * depth);
		rc <-= a;
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			for(i = 0; i < len ratios; i++) {
				env[i].ctl <-= (m, n);
				waves[i][0].ctl <-= (CFREQ, mula(n,ratios[i]));
			}
		CKEYOFF =>
			for(i = 0; i < len ratios; i++)
				env[i].ctl <-= (m, n);
		}
	}
}

mula(a: array of real, r: real): array of real
{
	for(i:=0; i < len a; i++)
		a[i] *= r;
	return a;
}
