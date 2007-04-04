Instrument: module {
	PATH: con "/dis/synth/instrument.dis";
	
	CFREQ, CKEYON, CKEYOFF, CATTACK, CDECAY, CSUSTAIN, 
	CRELEASE, CDELAY, CVOICE, CMIX, CHIGH, CLOW,
	CPOLE, CZERO, CRADIUS, CTUNE: con iota;

	BLOCK : con 8192;

	Context: adt {
		samplerate: real;
		channels: int;
		bps: int;
		config: string;
	};

	Inst: adt {
		c: Sample;
		ctl: Control;
	};

	Source: type array of ref Inst;
	Sample: type chan of (array of real, chan of array of real);
	Control: type chan of (int, array of real);
	
	getInstrument: fn(insts: Source, name: string): ref Inst;
};

IInstrument: module {
	init: fn(ctxt: Instrument->Context);
	synth: fn(s: Instrument->Source, 
		c: Instrument->Sample,
		ctl: Instrument->Control);
};
