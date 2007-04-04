implement Phase;

include "sys.m";
	sys: Sys;
	print, fildes, sprint, fprint: import sys;

include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
	arg: Arg;
include "rand.m";
	rand: Rand;
include "math.m";
	math: Math;
	
Phase: module{ init:fn(ctxt: ref Draw->Context, argv: list of string);};

width := 4;
ob:  ref Iobuf;
rule := 13;
loop := 1;
	time := 0.0;

Header: adt {
	tracks: array of ref Track;

};

Track: adt {
	inst: ref Inst;
	events: array of ref Event;
};

Event: adt {
	delta: real;
	ev: string;
	voice: int;
	note: int;
	vel: int;
};

Inst: adt {
	voice: int;
	rule: int;
	spb: int;
	octave: int;
	width: int;
};


init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg  Arg->PATH;
	rand = load Rand Rand->PATH;
	math = load Math Math->PATH;
	ob = bufio->fopen(fildes(1), Bufio->OWRITE);
	arg->init(argv);
	sys->pctl(Sys->NEWPGRP, nil);
	while((c := arg->opt()) != 0)
		case c {
		'l' =>
			loop = int arg->earg();
		'r' =>
			rule = int arg->earg();
		'w' =>
			width = int arg->earg();
                  * =>   sys->print("unknown option (%c)\n", c);
		}
	rand->init(rule);
	hdr := ref Header(array[4] of {
			ref Track(ref Inst(1, rand->rand(16), 1, 4, 4), nil), 
			ref Track(ref Inst(2, rand->rand(16), 4, 5, 5), nil), 
			ref Track(ref Inst(3, rand->rand(16), 1, 5, 4), nil), 
			ref Track(ref Inst(4, rand->rand(16), 1, 3, 4), nil)
		} );
		interleave(hdr);
		ob.flush();
}

iphase(in: ref Inst): array of ref Event
{
	return phase(in.voice, in.rule, in.spb, in.octave, in.width);
}

phase(voice: int, rule: int, spb: int, octave: int, width: int): array of ref Event
{
	bpm := 100.0;		# beats per minute
	stime := 60.0/bpm/real spb;
	velocity := 64;
	scale := rule2midi(int2revrule(2708));
	a := int2revrule(rule);
	events := array[2] of ref Event;
	nevent := 0;
	for(i := 0; i < width; i++){
		note := scale[i%len scale] + 12 * octave; 
		if(int a[i]){
			events[nevent++] = ref Event(time, "NoteOn", voice, note, velocity);
			time = stime;
			events[nevent++] = ref Event(time, "NoteOff", voice, note, velocity);
			if(nevent == len events)
				events = (array[len events * 2] of ref Event)[0:] = events;
		}else
			time += stime;
	}
	return events[:nevent];
}

int2revrule(n: int): array of byte
{
#	ncells := nbits(n);
	a := array[12] of byte;
	
	for(i := 0; i < len a; i++)
		a[i] = byte ((n >> i) & 1);
	return a;
}

rule2midi(a: array of byte): array of int
{
	b := array[8] of int;
	j := 0;
	for(i:=0; i<len a;i++)
		if(int a[i])
			b[j++] = i;
	return b[0:j];
}

nbits(n: int): int
{
	return int math->floor(math->log(real n)/math->log(2.0));
}

# we need three tracks, which we'll interleave like midi2skini
# a separate process will process events on each track.

interleave(hdr: ref Header)
{
	total := 0.0;
	for(;;){
		min := 10000.0;
		for(i:=0; i< len hdr.tracks; i++){
			if(len hdr.tracks[i].events == 0)
				hdr.tracks[i].events = iphase(hdr.tracks[i].inst);
			if(len hdr.tracks[i].events > 0 && hdr.tracks[i].events[0].delta < min)
				min = hdr.tracks[i].events[0].delta;
		}
		if(min == 10000.0)
			break;
		l : list of ref Event;
		for(i=0; i< len hdr.tracks; i++){
			if(len hdr.tracks[i].events > 0){
				if(hdr.tracks[i].events[0].delta <= min){
					l = hdr.tracks[i].events[0] :: l;
					hdr.tracks[i].events = hdr.tracks[i].events[1:];
				}else{
					hdr.tracks[i].events[0].delta -= min;
				}
			}
		}
		total += min;
		first := 1;
		for(; l != nil; l = tl l){
			e :=hd l;
			if(first){
				outevent(e);
				first = 0;
			}else{
				e.delta = 0.0;
				outevent(e);
			}
		}
		if(total >= 60.0){
			for(i=0; i< len hdr.tracks; i++)
				hdr.tracks[i].inst.rule = rand->rand(16);
			total = 0.0;
#			break;
		}
	}
}

outevent(m: ref Event)
{
	ob.puts(sprint("%s\t%.4g\t%d\t%d\t%d\n", m.ev,
		m.delta, m.voice, m.note, m.vel));
}