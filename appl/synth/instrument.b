implement Instrument;

include "sys.m";
include "instrument.m";
include "exprs.m";

samplerate := 44100.0;
channels := 2;
bps := 2;

getInstrument(insts: Source, config: string): ref Inst
{
	modpath: string;
	sys := load Sys Sys->PATH;
	
	exprs := load Exprs Exprs->PATH;
	Expr: import exprs;
	e := Expr.parse(config :: nil);
	if(e != nil)
		modpath = "/dis/synth/" + e.op() + ".dis";
	else{
		sys->print("parse: %s\n", config);
		modpath = "/dis/synth/" + config + ".dis";
	}
#	sys->print("%s %s\n", modpath, config);
	mod := load IInstrument modpath;
	if(mod == nil)
		return nil;
	ctxt := Context(samplerate, channels, bps, config);
	mod->init(ctxt);
	inst := ref Inst;
	inst.c =  chan of (array of real, chan of array of real);
	inst.ctl = chan of (int, array of real);
	spawn mod->synth(insts, inst.c, inst.ctl);
	return inst;
}
