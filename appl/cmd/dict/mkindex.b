implement Mkindex;

include "draw.m";

include "sys.m";
	sys: Sys;
	print, sprint: import sys;
include "libc.m";
	libc: Libc;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
	arg: Arg;
include "dictm.m";
	dict: Dictm; # current dictionary
	Entry: import dict;
include "utils.m";
	utils: Utils;
	err, fold, linelen, debug: import utils;
	
Mkindex: module
{
	init: fn(nil: ref Draw->Context, argl: list of string);
};

Dictinfo: adt{
	name: string;
	desc: string;
	path: string;
	indexpath: string;
	modpath: string;
};

dicts := array[] of {
	Dictinfo ("pgw",	"Project Gutenberg Webster Dictionary",	"/lib/dict/pgw",	"/lib/dict/pgwindex",	"/dis/dict/pgw.dis"),
	Dictinfo("simple", "Simple test dictionary", "/lib/dict/simple", "/lib/dict/simpleindex", "/dis/dict/simple.dis"),
	Dictinfo ("roget",	"Roget's Thesaurus from Project Gutenberg",	"/lib/dict/roget",	"/lib/dict/rogetindex", "/dis/dict/roget.dis"),
	Dictinfo ("wikipedia",	"Wikipedia",	"/n/d/enwik8",	"/n/d/enwik8index", "wikipedia.dis"),
};

bout, bdict: ref Iobuf;	#  output 

init(nil: ref Draw->Context, argl: list of string)
{
	sys = load Sys Sys->PATH;
	libc = load Libc Libc->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	utils = load Utils Utils->PATH;
	
	dictinfo := dicts[0];
	
	bout = bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	utils->init(bufio, bout);
	arg->init(argl);
	while((c := arg->opt()) != 0)
		case c {
			'd' =>
				p := arg->arg();
				if(p != nil)
					for(i := 0; i < len dicts; i++)
						if(p == dicts[i].name){
							dictinfo = dicts[i];
							break;
						}
				if(i == len dicts){
					err(sprint("unknown dictionary: %s", p));
					exit;
				}
			}
	dict = load Dictm dictinfo.modpath;
	if(dict == nil){
		err(sprint("can't load module %s: %r", dictinfo.modpath));
		exit;
	}
	bdict = bufio->open(dictinfo.path, Sys->OREAD);
	if(bdict == nil){
		err("can't open dictionary " + dictinfo.path);
		exit;
	}

	dict->init(bufio, utils, bdict, bout);
	
	ae := int bdict.seek(big 0, 2);
	for(a := 0; a < ae; a = dict->nextoff(a+1)) {
		linelen = 0;
		e := getentry(a);
		bout.puts(sprint("%d\t", a));
		linelen = 4;
		dict->printentry(e, 'h');
	}
	bout.flush();
	exit;
}

getentry(b: int): Entry
{
	dtop: int;
	ans : Entry;
	e := dict->nextoff(b+1);
	ans.doff = big b;
	if(e < 0) {
		dtop = int bdict.seek(big 0, 2);
		if(b < dtop){
			e = dtop;
		}else{
			err("couldn't seek to entry");
			ans.start = nil;
		}
	}
	n := e-b;
	if(n){
		ans.start = array[n] of byte;
		bdict.seek(big b, 0);
		n = bdict.read(ans.start, n);
		ans.start = ans.start[:n];
	}
	return ans;
}
