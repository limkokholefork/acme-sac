implement IInstrument;

include "instrument.m";
	instrument: Instrument;
	Context, Source, Sample, Control, 
	CKEYOFF, CKEYON: import Instrument;
	getInstrument: import instrument;

channels: int;
samplerate: real;

init(ctxt: Context)
{
	instrument = load Instrument Instrument->PATH;
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
}

synth(inst: Source, c: Sample, ctl: Control)
{
	mix := getInstrument(inst, "mixer 0.7");
	index := 0;

	for(;;) alt {
	(a, rc ) := <-c =>
		mix.c <-= (a, rc);
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			inst[index].ctl <-= (m, n);
		CKEYOFF =>
			inst[index].ctl <-= (m, n);
			index++;
			index %= len inst;
		}
	}
}
