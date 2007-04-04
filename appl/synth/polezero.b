implement IInstrument;

include "instrument.m";
	Context, Source, Sample, Control, 
	BLOCK, CPOLE: import Instrument;

channels: int;
samplerate: real;

init(ctxt: Context)
{
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
}
# y(n) = b₀x(n) + b₁x(n-1) - a₁y(n-1)
synth(nil: Source, c: Sample, ctl: Control)
{
	last := array[channels] of {* => 0.0};
	lastout := array[channels] of {* => 0.0};
	b := array[2] of {1.0, -1.0};		#gain
	a := array[2] of {1.0, -0.99};
	x := array[BLOCK * channels] of real;

	for(;;) alt {
	(y, rc) := <-c =>
		x[0:] = y;
		for(j := 0; j < channels; j++){
			y[j] = b[0] * x[j] + b[1] * last[j] - a[1] * lastout[j];
			for(i := channels+j; i < len y; i += channels)
				y[i] = b[0] * x[i] + b[1] * x[i-channels] - a[1] * y[i-channels];
		}
		lastout[0:] = y[len y-channels:len y];
		last[0:] = x[len y - channels:len y];
		rc <-= x;
	(m, n) := <-ctl =>
		case m {
		CPOLE =>
			a[1] = -n;
		}
	}
}

