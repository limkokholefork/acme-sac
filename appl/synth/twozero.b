implement IInstrument;

include "math.m";
	math: Math;
	sin, cos, Pi, pow, sqrt: import math;
include "instrument.m";
	Context, Source, Sample, Control, BLOCK, CFREQ, CRADIUS: import Instrument;

channels: int;
samplerate: real;

init(ctxt: Context)
{
	math = load Math Math->PATH;
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
}

# y(n) = b₀x(n) + b₁x(n-1) + b₂x(n-1)
synth(nil: Source, c: Sample, ctl: Control)
{
	b := array [3] of {2.0, 0.0, 0.0};
	radius := 0.99;
	freq := samplerate / 4.0;
	b[2] = radius * radius;
	b[1] = -2.0 * radius * cos(2.0 * Pi * freq/samplerate);
	x := array[BLOCK * channels] of real;
	last := array[2*channels] of {* => 0.0};

	for(;;) alt {
	(y, rc) := <-c =>
		x[0:] = y;
		for(j := 0; j < channels; j++){
			y[j] = b[0] * x[j] + b[1] * last[channels+j] + b[2] * last[j];
			y[j + channels] = b[0] * x[channels+j] + b[1] * x[j] + b[2] * last[channels+j];
			for(i := channels*2 + j; i < len y; i += channels)
				y[i] = b[0] * x[i] + b[1] * x[i-channels] + b[2] * x[i-channels*2];
		}
		last[0:] = x[len y - 2*channels:len y];
		rc <-= y;
	(m, n) := <-ctl =>
		case m {
		CFREQ =>
			freq = n;
		CRADIUS =>
			radius = n;
		}
		b[2] = radius * radius;
		b[1] = -2.0 * radius * cos(2.0 * Pi * freq/samplerate);
		if(b[1] > 0.0)
			b[0] = 1.0 / (1.0 + b[1] + b[2]);
		else
			b[0] = 1.0 / (1.0 - b[1] + b[2]);
		b[1] *= b[0];
		b[2] *= b[0];
	}
}
