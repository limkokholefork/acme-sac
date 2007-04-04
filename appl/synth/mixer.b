implement IInstrument;

include "instrument.m";
	Context, Source, Sample, Control, BLOCK: import Instrument;
include "exprs.m";
	exprs: Exprs;
	Expr: import exprs;
channels: int;
samplerate: real;
mix := 0.5;
init(ctxt: Context)
{
	exprs = load Exprs Exprs->PATH;
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
	e := Expr.parse(ctxt.config :: nil);
	if(e != nil && e.islist()){
		args := e.args();
#		sys->print("waveloop: %s\n", (hd args).text());
		if(args != nil)
			mix = real (hd args).text();
	}
}

synth(inst: Source, c: Sample, nil: Control)
{

	t := array[len inst] of array of real;
	b := array[len inst] of array of real;
	for(i := 0; i < len inst; i++)
		b[i] = array[BLOCK * channels] of { * => 0.0};

	for(;;) alt {
	(a, rc) := <-c =>
		wrc := chan of array of real;
		for(i = 0; i < len inst; i++)
			if(inst[i] != nil)
				inst[i].c <-= (b[i][0:len a], wrc);
# concurrency!
# they may not come back in the same order we sent them
		j := 0;
		for(i = 0; i < len inst; i++)
			if(inst[i] != nil)
				t[j++] =<- wrc; 
		for(i = 0; i < len a; i++){
			a[i] = 0.0;
			for(k := 0; k < j; k++)
				if(t[k] != nil)
					a[i] += t[k][i] * mix;
		}
		rc <-= a;
	}
}
