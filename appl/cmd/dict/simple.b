implement Dictm;

include "draw.m";
include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "utils.m";
	utils: Utils;
	outrune, outnl: import utils;
include "dictm.m";

bdict, bout : ref Iobuf;

init(b: Bufio, u: Utils, bd, bo: ref Iobuf )
{
	sys = load Sys Sys->PATH;
	bufio = b;
	bdict = bd;
	bout = bo;
	utils = u;
}

# Routines for handling dictionaries in UTF, headword
# separated from entry by tab, entries separated by newline.

printentry(e: Entry, cmd: int)
{
	s := string e.start;
	for(i := 0; i < len s; i++)
		if(s[i] == '\t')
			if(cmd == 'h')
				break;
			else
				outrune(' ');
		else if(s[i] == '\n')
			break;
		else
			outrune(s[i]);
	outnl(0);
}

nextoff(fromoff: big): big
{
	if(bdict.seek(big fromoff, 0) < big 0)
		return big -1;
	if(bdict.gets('\n') == nil)
		return big -1;
	return bdict.offset();
}

printkey()
{
	bout.puts("No pronunciation key.\n");
}


mkindex()
{
}
