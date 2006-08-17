implement Reduce;


# reduce takes one or more files and sorts them. then
# gathers like keys and spawns the reduce process for each key,
# and gathers result.
include "sh.m";
include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "mapred.m";
	reducer : Reducer;

Incr: con 2000;		# growth quantum for record array

Reduce: module {
	init:fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;

	args = tl args;
	if(len args != 1)
		exit;
	reducer = load Reducer "/dis/mapreduce/" + hd args + ".dis";
	if(reducer == nil){
		warn("reducer", "");
		exit;
	}
	io := bufio->fopen(sys->fildes(0), Sys->OREAD);
	if(io == nil)
		return;
	out := bufio->fopen(sys->fildes(1), Sys->OWRITE);
	if(out == nil)
		return;
	last := "";
	values : chan of string;
	done := chan of int;
	while ((s := io.gets('\n')) != nil) {
		(nf, f) := sys->tokenize(s, " \t\n\r");
		if(nf != 2)
			continue;
		if(hd f == last){
			values <-= hd tl f;
		}else{
			if(last != ""){
				values <-= nil;
				<-done;
			}
			last = hd f;
			values = chan of string;
			spawn emiter(out, last, values, done);
			values <-= hd tl f;
		}
	}
	if(last != ""){
		values <-= nil;
		<-done;
	}
	out.close();
}

emiter(out: ref Iobuf, key: string, input: chan of string, done: chan of int)
{
	sync := chan of int;
	output:= chan of string;
	spawn reduceworker(sync, key, input, output);
	<-sync;
	loop: for(;;) alt {
	s := <-output =>
		out.puts(sys->sprint("%s %s\n", key, s));
	<-sync =>
		break loop;
	}
	done <-= 1;
}

reduceworker(sync: chan of int, k: string, input: chan of string, emit: chan of string)
{
	sync <-= sys->pctl(0, nil);
	reducer->reduce(k, input, emit);
	sync <-= 1;
}

warn(why: string, f: string)
{
	sys->fprint(sys->fildes(2), "mapred: %s %q: %r\n", why, f);
}
