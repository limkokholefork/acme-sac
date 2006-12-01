implement Complete;

include "sys.m";
	sys: Sys;
	open, read, print, fprint, dirread, OREAD, FD, Dir, DMDIR: import sys;
include "string.m";
	str: String;
include "complete.m";

include "readdir.m";
	readdir: Readdir;

init()
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	readdir = load Readdir Readdir->PATH;
}


longestprefixlength(a, b: string, n: int): int
{
	for(i := 0; i < n; i++){
		if(a[i] != b[i])
			break;
	}
	return i;
}

blankcompletion: Completion;

complete(dir, s: string): ref Completion
{

	if(str->splitl(s, "/").t1 != nil)
		return nil;

	fd := open(dir, OREAD);
	if(fd == nil)
		return nil;

	(da, n) := readdir->readall(fd, 0);
	if(n <= 0)
		return nil;

	c := ref blankcompletion;

	name := array[n] of string;
	mode := array[n] of int;
	length := len s;
	nfile := 0;
	minlen := 1000000;
	for(i := 0; i < n; i++)
		if(str->prefix(s,da[i].name)){
			name[nfile] = da[i].name;
			mode[nfile] = da[i].mode;
			if(minlen > len da[i].name)
				minlen = len da[i].name;
			nfile++;
		}

	if(nfile > 0){
		for(i = 1; i < nfile; i++)
			minlen = longestprefixlength(name[0], name[i], minlen);

		c.complete = (nfile == 1);
		c.advance = c.complete || (minlen > length);
		c.str = name[0][length:minlen];
		if(c.complete){
			if(mode[0]&DMDIR)
				c.str[minlen++ - length] = '/';
			else
				c.str[minlen++ - length] = ' ';
		}
		c.nmatch = nfile;
	}else{
		for(i = 0; i < n; i++){
			name[i] = da[i].name;
			mode[i] = da[i].mode;
		}
		nfile = n;
		c.nmatch = 0;
	}
	c.filename = name;
	for(i = 0; i < nfile; i++)
		if(mode[i] & DMDIR)
			c.filename[i][len c.filename[i]] = '/';

	c.nfile = nfile;
	return c;
}
