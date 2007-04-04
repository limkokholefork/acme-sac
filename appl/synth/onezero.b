implement IInstrument;

include "instrument.m";
	Context, Source, Sample, Control, 
	BLOCK, CZERO: import Instrument;

channels: int;
samplerate: real;

init(ctxt: Context)
{
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
}
# y(n) = b₀x(n) + b₁x(n-1)
synth(nil: Source, c: Sample, ctl: Control)
{
	last := array[channels] of {* => 0.0};
	b := array[2] of {1.0, 1.0};
	x := array[BLOCK * channels] of real;
	b0 := array[BLOCK] of { * => 1.0};
	b1 := array[BLOCK] of { * => 0.0};

	for(;;) alt {
	(y, rc) := <-c =>
		x[0:] = y;
		for(j := 0; j < channels; j++){
			k := 0;
			y[j] = b0[k] * x[j] + b1[k++] * last[j];
			for(i := channels+j; i < len y; i += channels)
				y[i] = b0[k] * x[i] + b1[k++] * x[i-channels];
		}
		last[0:] = x[len y - channels:len y];
		rc <-= y;
	(m, n) := <-ctl =>
		case m {
		* =>
			for(i := 0; i < len n; i++){
				if(n[i] > 0.0)
					b0[i] = 1.0 / (1.0 + n[i]);
				else
					b0[i] = 1.0 / (1.0 - n[i]);
				b1[i] = n[i] * b0[i];
#				b1[i] = n[i];
#				b1[i] = 1.0;
#				b0[i] = 1.0;
			}
		}
	}
}

