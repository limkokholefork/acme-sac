implement IInstrument;

include "instrument.m";
	Context, Source, Sample, Control, 
	CKEYON, CKEYOFF, CATTACK, CDECAY, CSUSTAIN,
	CRELEASE: import Instrument;
include "exprs.m";
	exprs: Exprs;
	Expr: import exprs;

channels: int;
samplerate: real;
ATTACK, DECAY, RELEASE, SUSTAIN, DONE: con iota;

state:= DONE;
target := 1.0;
value := 0.0;
attack := 1.0;
decay := 1.0;
sustain := 0.1;
release := 0.1;
rate := 1.0;

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
		if(len args == 4){
			control(CATTACK, real (hd args).text());
			args = tl args;
			control(CDECAY, real (hd args).text());
			args = tl args;
			control(CSUSTAIN, real (hd args).text());
			args = tl args;
			control(CRELEASE, real (hd args).text());
		}
#		config = (hd args).text();
	}
}

synth(inst: Source, c: Sample, ctl: Control)
{
	wrc := chan of array of real;
	for(;;) alt{
	(a, rc) := <-c =>
		if(inst[0] == nil)
			continue;
		if(state != DONE){
			inst[0].c <-= (a, wrc);
			a =<- wrc;
		}
		for(i := 0; i < len a; i += channels){
			case (state) {
			ATTACK =>
				value += rate;
				if (value >= target) {
					value = target;
					rate = decay;
					target = sustain;
					state = DECAY;
				}
			DECAY =>
				value -= decay;
				if (value <= sustain) {
					value = sustain;
					rate = 0.0;
					state = SUSTAIN;
				}
			RELEASE =>
				value -= release;
				if (value <= 0.0) {
					value = 0.0;
					state = DONE;
				}
			}
			for(j := 0; j < channels && i < len a; j++)
				a[i+j] *= value;
		}
		rc <-= a;
	(m, r) := <-ctl =>
		control(m, r[0]);
	}
}

control(m: int, r: real)
{
	case (m) {
	CKEYON =>
		value = 0.0;
		target = 1.0;
		rate = attack;
		state = ATTACK;
	CKEYOFF =>
		target = 0.0;
		rate = release;
		state = RELEASE;
	CATTACK =>
		attack = 1.0 / (r * samplerate);
	CDECAY =>
		decay = 1.0 / (r * samplerate);
	CSUSTAIN =>
		sustain = r;
	CRELEASE =>
		release = sustain / (r * samplerate);
	}
}
