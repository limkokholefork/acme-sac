implement Sequencer;

include "sys.m";
	sys: Sys;
	fprint, fildes, sprint, print: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "math.m";
	math: Math;
	sin, cos, Pi, pow, sqrt: import math;
include "rand.m";
	rand: Rand;
include "instrument.m";
	instrument: Instrument;
	CVOICE, CKEYON, CKEYOFF, BLOCK, Inst: import Instrument;
	getInstrument: import instrument;
	
midi2pitch:= array[129] of {
8.18,8.66,9.18,9.72,10.30,10.91,11.56,12.25,
12.98,13.75,14.57,15.43,16.35,17.32,18.35,19.45,
20.60,21.83,23.12,24.50,25.96,27.50,29.14,30.87,
32.70,34.65,36.71,38.89,41.20,43.65,46.25,49.00,
51.91,55.00,58.27,61.74,65.41,69.30,73.42,77.78,
82.41,87.31,92.50,98.00,103.83,110.00,116.54,123.47,
130.81,138.59,146.83,155.56,164.81,174.61,185.00,196.00,
207.65,220.00,233.08,246.94,261.63,277.18,293.66,311.13,
329.63,349.23,369.99,392.00,415.30,440.00,466.16,493.88,
523.25,554.37,587.33,622.25,659.26,698.46,739.99,783.99,
830.61,880.00,932.33,987.77,1046.50,1108.73,1174.66,1244.51,
1318.51,1396.91,1479.98,1567.98,1661.22,1760.00,1864.66,1975.53,
2093.00,2217.46,2349.32,2489.02,2637.02,2793.83,2959.96,3135.96,
3322.44,3520.00,3729.31,3951.07,4186.01,4434.92,4698.64,4978.03,
5274.04,5587.65,5919.91,6271.93,6644.88,7040.00,7458.62,7902.13,
8372.02,8869.84,9397.27,9956.06,10548.08,11175.30,11839.82,12543.85,
13289.75};

samplerate := 44100.0;
channels := 2;
bps := 2;
bpm := 120;

Sequencer: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

modinit()
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	math = load Math Math->PATH;
	math->FPcontrol(0, math->INVAL|math->OVFL|math->UNFL|math->ZDIV);
	instrument = load Instrument Instrument->PATH;
	rand = load Rand Rand->PATH;
	audioctl("rate 44100");
#	midi2pitch = mkmidi();
}


init(nil: ref Draw->Context, argv: list of string)
{
	modinit();
	sys->pctl(Sys->NEWPGRP, nil);
	argv = tl argv;
	fname:string;
	if(len argv == 0)
		return;
	else if(len argv == 1)
		fname = nil;
	if(len argv >= 2)
		fname = hd tl argv;;
	iname := hd argv;
	inst := getInstrument(nil, iname);
	linechan := chan of string;
	spawn looper(fname, linechan, 0);
	sync := chan of int;
	spawn skiniplay(sync, linechan, inst);
	pid := <-sync;
	<-sync;
	kill(pid, "killgrp");
}

looper(file: string, line: chan of string, loop: int)
{
	io: ref Iobuf;
	if(file != nil)
		io = bufio->open(file, Bufio->OREAD);
	else
		io = bufio->fopen(sys->fildes(0), Bufio->OREAD);

	for(;;) {
		while((s := io.gets('\n')) != nil)
			line <-= s;
		if(!loop){
			line <-= nil;
			return;
		}
		io.seek(big 0, Bufio->SEEKSTART);
	}
}

skiniplay(sync: chan of int, linechan: chan of string, inst: ref Inst)
{
	sync <-= sys->pctl(0, nil);
	ob := bufio->open("#A/audio", Bufio->OWRITE);
#	ob := bufio->open("/n/d/bach.raw", Bufio->OWRITE);
#	ob := bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	buf := array[1] of real;

	rc := chan of array of real;
	out := array[BLOCK*channels] of { * => 0.0};
	while((s := <-linechan) != nil) {
		(n, flds) := sys->tokenize(s, " \n\t\r");
		if(n == 0)
			continue;
		else if((hd flds)[0:2] == "//")
			continue;
		t := real hd tl flds;
		t *= samplerate;
		voice := int hd tl tl flds;
		if(t > 0.0){
			nsamples := big t & 16rFFFFFFFE;
			block := BLOCK;
			while(nsamples > big 0){
				if(big block > nsamples)
					block = int nsamples;
				inst.c <-= (out[:block*channels], rc);
				b := norm2raw(<-rc);
				ob.write(b, len b);
				nsamples -= big block;
			}
		}
		if(voice >= 8 || voice < 0)
			continue;
		buf[0] = real voice;
		inst.ctl <-= (CVOICE, array[1] of {real voice});
		case hd flds {
		"NoteOn" =>
			note := int hd tl tl tl flds;
			inst.ctl <-= (CKEYON, array[1] of {midi2pitch[note%len midi2pitch]});
		"NoteOff" =>
			inst.ctl <-= (CKEYOFF, buf);
		}
	}
	ob.flush();
	sync <-= 0;
}

kill(pid: int, note: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}

audioctl(s: string): int
{
	fd := sys->open("#A/audioctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", s) < 0)
		return -1;
	return 0;
}

mkmidi(): array of real
{
	a := array[128] of real;
	for(i:=0;i < len a; i++){
		a[i] = 220.0 * math->pow(2.0, (real i-57.0)/12.0);
		sys->print("midi %g\n", a[i]);
	}
	return a;
}

norm2raw(v: array of real): array of byte
{
	b:=array[len v *2] of byte;
	j:=0;
	for(i:=0;i<len v;i++){
		sample := v[i] * 32767.0;
		if(sample> 32767.0)
			sample = 32767.0;
		else if(sample < -32767.0)
			sample = -32767.0;
		b[j++] = byte sample;
		b[j++] = byte (int sample >>8);
	}
	return b;
}
