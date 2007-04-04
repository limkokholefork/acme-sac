implement IInstrument;

include "sys.m";
include "math.m";
	math: Math;
	sin, cos, Pi, pow, sqrt: import math;
include "instrument.m";
	Context, Source, Sample, Control, BLOCK, CFREQ, CRADIUS: import Instrument;
include "rand.m";
	rand: Rand;

channels: int;
samplerate: real;
config := "sinewave";

init(ctxt: Context)
{
	sys := load Sys Sys->PATH;
	math = load Math Math->PATH;
	rand = load Rand Rand->PATH;
	exprs = load Exprs Exprs->PATH;
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
}

synth(nil: Source, c: Sample, ctl: Control)
{
	MAX := 65536;

	for(;;) alt {
	(a, rc) := <-c =>
		for(i := 0; i < len a; i += channels){
				n := 2.0 * real rand->rand(MAX) / real(MAX + 1);
				n -= 1.0;
			for(j := 0; j < channels && i < len a; j++){
				a[i+j] = n;
			}
		}
		rc <-= a;
	(m, n) := <-ctl =>
		;
	}
}


noise(): array of real
{
	b := array[LENGTH] of real;
	MAX := 65536;
	for(i := 0; i < LENGTH; i++)
		b[i] = 2.0 * real rand->rand(MAX) / real(MAX + 1);
	return b;
}
