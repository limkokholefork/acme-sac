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
	
midi2pitch: array of real;

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
	midi2pitch = mkmidi();
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
	for(i:=0;i < len a; i++)
		a[i] = 220.0 * math->pow(2.0, (real i-57.0)/12.0);
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
