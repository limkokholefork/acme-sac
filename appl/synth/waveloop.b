implement IInstrument;

include "sys.m";
include "math.m";
	math: Math;
	sin, cos, Pi, pow, sqrt: import math;
include "instrument.m";
	Context, Source, Sample, Control, BLOCK, CFREQ, CRADIUS: import Instrument;
include "exprs.m";
	exprs: Exprs;
	Expr: import exprs;
include "rand.m";
	rand: Rand;

channels: int;
samplerate: real;
config := "sinewave";

init(ctxt: Context)
{
	sys := load Sys Sys->PATH;
	math = load Math Math->PATH;
	rand = load Rand Rand->PATH;
	exprs = load Exprs Exprs->PATH;
	channels = ctxt.channels;
	samplerate = ctxt.samplerate;
	e := Expr.parse(ctxt.config :: nil);
	if(e != nil && e.islist()){
		args := e.args();
#		sys->print("waveloop: %s\n", (hd args).text());
		if(args != nil)
			config = (hd args).text();
	}
}

synth(nil: Source, c: Sample, ctl: Control)
{
	data: array of real;
	rate := 1.0;
	time := 0.0;
	index := 0;
	alpha : real;

	case config {
	"sinewave" => data = sinewave();
	"halfwave" => data = halfwave();
	"sineblnk" => data = sineblnk();
	"fwavblnk" => data = fwavblnk();
	"impuls" => data = impuls(10);
	"noise" => data = noise();
	"squarewave" => data = squarewave();
	"sawwave" => data = sawwave();
	}

	for(;;) alt {
	(a, rc) := <-c =>
		n := len data;
		for(i := 0; i < len a; i += channels){
			while(time < 0.0)
				time += real n;
			while(time >= real n)
				time -= real n;
			index = int time;
			alpha = time - real index;
#			index *= channels;
			for(j := 0; j < channels && i < len a; j++){
				a[i+j] = data[index%n];
				a[i+j] += (alpha * (data[(index+channels)%n] - a[i+j]));
				index++;
			}
			time += rate;
		}
		rc <-= a;
	(m, n) := <-ctl =>
		if(m == CFREQ){
			rate = (real len data * n[0]) / samplerate;
			time = 0.0;
			index = 0;
		}
	}
}


LENGTH: con 256;
halfwave(): array of real
{
	b := array[LENGTH] of { * => 0.0};
	for(i := 0; i < LENGTH/2; i++)
		b[i] = sin(real i * 2.0 * Pi / real LENGTH);
	return b;
}

sinewave(): array of real
{
	b := array[LENGTH] of { * => 0.0};
	for(i := 0; i < LENGTH; i++)
		b[i] = sin(real i * 2.0 * Pi / real LENGTH);
	return b;
}

sineblnk(): array of real
{
	b := sinewave();
	for(i := 0; i < LENGTH/2; i++)
		b[i] = b[2*i];
	for(i = LENGTH/2; i < LENGTH; i++)
		b[i] = 0.0;
	return b;
}

sawwave(): array of real
{
	b := array[LENGTH] of { * => 0.0};
	for(i:=0; i < LENGTH/2; i++) 
		b[i] = real i / real (LENGTH/2) - 1.0;
	for(i=LENGTH/2; i < LENGTH; i++) 
		b[i] = real i / real (LENGTH/2);
	return b;
}

squarewave(): array of real
{
	b := sinewave();
	for(i := 0; i < LENGTH; i++){
		if(b[i] >= 0.0)
			b[i] = 1.0;
		else
			b[i] = -1.0;
	}
	return b;
}

fwavblnk(): array of real
{
	b := sineblnk();
	for(i:=0;i<LENGTH/4;i++)
		b[i+LENGTH/4] = b[i];
	return b;
}

impuls(n: int): array of real
{
	b := array[LENGTH] of real;
	for(i := 0; i < LENGTH; i++){
		t := 0.0;
		for(j := 1; j <= n; j++)
			t += cos(real i * real j * 2.0 * Math->Pi / real LENGTH);
		b[i] = t * real n;
	}
	return b;
}

noise(): array of real
{
	b := array[LENGTH] of real;
	MAX := 65536;
	for(i := 0; i < LENGTH; i++)
		b[i] = 2.0 * real rand->rand(MAX) / real(MAX + 1);
	return b;
}
