implement IInstrument;

include "instrument.m";
	Context, Source, Sample, Control, 
	CDELAY, CMIX: import Instrument;
include "exprs.m";
	exprs: Exprs;
	Expr: import exprs;

channels: int;
samplerate: real;
delay := 0.0;   # in seconds
mix := 0.5;

init(ctxt: Context)
{
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
	exprs = load Exprs Exprs->PATH;
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
	e :=Expr.parse(ctxt.config :: nil);
	if(e != nil && e.islist()){
		args := e.args();
		if(args != nil && !(hd args).islist()){
			delay = real (hd args).text();
			args = tl args;
		}
		if(args != nil && !(hd args).islist())
			mix = real (hd args).text();
	}
}

synth(nil: Source, c: Sample, ctl: Control)
{
	inputs := array[int (2.0 * samplerate * real channels)] of { * => 0.0};
	lastout := 0.0;
	inpoint := 0;
	outpoint := inpoint - int (delay * samplerate * real channels);

	while(outpoint < 0)
		outpoint += len inputs;
	outpoint %= len inputs;

	for(;;) alt {
	(a, rc) := <-c =>
		for(i := 0; i < len a; i++){
			inputs[inpoint++] = a[i];
			inpoint %= len inputs;
			lastout = inputs[outpoint++];
			outpoint %= len inputs;
			echo := lastout * mix;
			echo += a[i] * (1.0 - mix);
			a[i] = echo;
		}
		rc <-= a;
	(m, n) := <-ctl =>
		if(len n < 1)
			continue;
		case (m) {
		CDELAY =>
			outpoint =  inpoint - int (n[0] * samplerate * real channels);
			while(outpoint < 0)
				outpoint += len inputs;
			outpoint %= len inputs;
		CMIX =>
			mix = n[0];
		}
	}
}
