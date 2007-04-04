implement IInstrument;

include "instrument.m";
	instrument: Instrument;
	Context, Source, Sample, Control, 
	CPOLE, BLOCK: import Instrument;
	getInstrument: import instrument;

channels: int;
samplerate: real;

init(ctxt: Context)
{
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
	instrument = load Instrument Instrument->PATH;
}
# y(n) = b₀x(n) - a₁y(n-1)
synth(nil: Source, c: Sample, ctl: Control)
{
	lastout := array[channels] of {* => 0.0};
	b := array[1] of {0.2};		#gain
	a := array[2] of {1.0, -0.9};
#	lfo := getInstrument(nil, "lfo 0.07 -0.8 0.4");
	depth := 0.2;
	a1 := array[1] of {-0.9};
	
	for(;;) alt {
	(x, rc) := <-c =>
		for(j := 0; j < channels; j++){
			k := 0;
			x[j] = b0(a1[k]) * x[j] - a1[k] * lastout[j];
			if(k < len a1 - 1)
				k++;
			for(i := channels+j; i < len x; i += channels){
				x[i] = b0(a1[k]) * x[i] - a1[k] * x[i-channels];
				if(k < len a1 - 1)
					k++;
			}
		}
		lastout[0:] = x[len x-channels:];
		rc <-= x;
	(m, n) := <-ctl =>
		a1 = n;
#		case m {
#		CPOLE =>
#			a[1] = -n;
#			if(n > 0.0)
#				b[0] = 1.0 - n;
#			else
#				b[0] = 1.0 + n;
#		}
	}
}

b0(n: real): real
{
	if(n > 0.0)
		return 1.0 - n;
	else
		return 1.0 + n;
}
