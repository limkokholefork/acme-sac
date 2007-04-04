implement IInstrument;

include "instrument.m";
	Context, Source, Sample, Control, 
	CPOLE: import Instrument;

channels: int;
samplerate: real;

init(ctxt: Context)
{
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
}
# y(n) = x⁳ - x
synth(nil: Source, c: Sample, ctl: Control)
{
	# perform "tabl lookup" using a polynomial
	# calculation (x^3 - x), which approximates
	# the jet sigmoid behavior.

	for(;;) alt {
	(x, rc) := <-c =>
		for(i := 0; i < len x; i += channels){
			for(j := 0; j < channels && i < len x; j++){
				r := x[i+j];
				n := r * (r * r - 1.0);
				if(n > 1.0)
					n = 1.0;
				if(n < -1.0)
					n = -1.0;
				x[i+j] = n;
			}
		}
		rc <-= x;
	(m, n) := <-ctl =>
		;
	}
}
