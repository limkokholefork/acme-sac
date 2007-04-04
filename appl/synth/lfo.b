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
high := 1.0;
low := -1.0;
range :real;
rate := 1.0;
time := 0.0;
index := 0;
data: array of real;
freq := 0.5;

init(ctxt: Context)
{
	sys = load Sys Sys->PATH;
	instrument = load Instrument Instrument->PATH;
	math = load Math Math->PATH;
	exprs = load Exprs Exprs->PATH;
	channels = 1;
	samplerate = ctxt.samplerate;
	e := Expr.parse(ctxt.config :: nil);
	if(e != nil && e.islist()){
		args := e.args();
		if(args != nil){
			freq = real (hd args).text();
			args = tl args;
		}
		if(args != nil){
			low = real (hd args).text();
			args = tl args;
		}
		if(args != nil){
			high = real (hd args).text();
		}
	}
	sys->print("samplerate %f, freq %f\n", samplerate, freq);
	range = (high - low)/2.0;
	data = sinewave();
	control(CFREQ, freq);
}

# lfo's don't need a high sampling rate and only need one channel.
synth(nil: Source, c: Sample, ctl: Control)
{
	for(;;) alt {
	(a, rc) := <-c =>
		n := len data;
		for(i := 0; i < len a; i += channels){
			while(time < 0.0)
				time += real n;
			while(time >= real n)
				time -= real n;
			index = int time;
			alpha := time - real index;
			for(j := 0; j < channels && i < len a; j++){
				r := data[index%n];
				r += (alpha * (data[(index+channels)%n] - r));
				a[i+j] =  r * range + range + low;
				index++;
			}
			time += rate;
		}
#		sys->print("lfo %f\n", a[0]);
		rc <-= a;
	(m, n) := <-ctl =>
		control(m,n[0]);
	}
}

control(m: int, n: real)
{
	case m{
	CFREQ =>
		rate = (real len data * n) / samplerate;
		sys->print("set rate %f\n", rate);
		time = 0.0;
		index = 0;
	CHIGH =>
		high = n;
		range = (high - low)/2.0;
	CLOW =>
		low = n;
		range = (high - low)/2.0;
	}

}

LENGTH: con 256;
sinewave(): array of real
{
	b := array[LENGTH] of { * => 0.0};
	for(i := 0; i < LENGTH; i++)
		b[i] = sin(real i * 2.0 * Pi / real LENGTH);
	return b;
}
