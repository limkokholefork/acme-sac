implement IInstrument;

include "instrument.m";
	Context, Source, Sample, Control, 
	CDELAY, CMIX: import Instrument;
include "exprs.m";
	exprs: Exprs;
	Expr: import exprs;

channels: int;
samplerate: real;
mix := 0.5;
delay := 0.0;   # in seconds
outpointer: real;
alpha, omalpha: real;
inpoint := 0;
inputs: array of real;
outpoint: int;

init(ctxt: Context)
{
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
	exprs = load Exprs Exprs->PATH;
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
	inputs = array[int (2.0 * samplerate * real channels)] of { * => 0.0};
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
	control(CDELAY, delay);
}

synth(nil: Source, c: Sample, ctl: Control)
{
	lastout := 0.0;
	toggle := 1;

	for(;;) alt {
	(a, rc) := <-c =>
		for(i := 0; i < len a; i++){
			inputs[inpoint++] = a[i];
			inpoint %= len inputs;
			if(toggle){
				lastout = inputs[outpoint] * omalpha;
				if(outpoint+1 < len inputs)
					lastout += inputs[outpoint+1] * alpha;
				else
					lastout += inputs[0] * alpha;
			}
			toggle ^= 1;
			outpoint++;
			outpoint %= len inputs;
	
			echo := lastout * mix;
			echo += a[i] * (1.0 - mix);
			a[i] = echo;
#			a[i] = lastout;
		}
		rc <-= a;
	(m, n, nil) := <-ctl =>
		control(m,n);
	}
}

control(m: int, n: real)
{
	case (m) {
	CDELAY =>
		if(n >= real len inputs){
			outpointer = real inpoint + 1.0;
		}else if(n < 0.0){
			outpointer = real inpoint;
		}else{
			outpointer = real inpoint - n;
		}
		while(outpointer < 0.0)
			outpointer += real len inputs;
		outpoint = int outpointer;
		alpha = outpointer - real outpoint;
		omalpha = 1.0 - alpha;
	CMIX =>
		mix = n;
	}

}
