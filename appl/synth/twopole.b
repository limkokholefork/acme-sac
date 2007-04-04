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

# twopole filter
# y(n) = b₀x(n) - a₁y(n-1) - a₂y(n-1)
synth(nil: Source, c: Sample, ctl: Control)
{
	lastout := array[channels*2] of {* => 0.0};
	b := array[1] of {0.005};		#gain
	a := array[3] of {1.0, 0.0, 0.0};
	radius := 0.99;
	freq := 500.0;
	a[1] = -2.0 * radius * cos(2.0 * Pi * freq/samplerate);
	a[2] = radius**2;
	x := array[BLOCK * channels] of real;

	for(;;) alt {
	(y, rc) := <-c =>
		x[0:] = y;
		for(j := 0; j < channels; j++){
			y[j] = b[0] * x[j] - a[1] * lastout[channels+j] - a[2] * lastout[j];
			y[j + channels] = b[0] * x[j + channels] - a[1] * y[j] - a[2] * lastout[channels + j];
			for(i := channels*2+j; i < len y; i += channels)
				y[i] = b[0] * x[i]  - a[1] * y[i-channels] - a[2] * y[i-channels*2];
		}
		lastout[0:] = y[len y - 2*channels:];
		rc <-= y;
	(m, n) := <-ctl =>
		case m {
		CFREQ =>
			freq = n;
		CRADIUS =>
			radius = n;
		}
		a[1] = -2.0 * radius * cos(2.0 * Pi * freq/samplerate);
		a[2] = radius * radius;
#normalize
		re := 1.0 - radius + (a[2] - radius) * cos(2.0 * Pi * 2.0 * freq / samplerate);
		im := (a[2] - radius) * sin(2.0 * Pi * freq/samplerate);
		b[0] = sqrt(pow(re, 2.0) + pow(im, 2.0));
	}
}
