implement Cryptfile;
include "sys.m";
	sys: Sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Navigator: import styxservers;
	nametree: Nametree;
	Tree: import nametree;
include "keyring.m";
	keyring: Keyring;

stderr: ref Sys->FD;
fd: ref Sys->FD;
is: ref Keyring->IDEAstate;
BUFSIZE : con 512;  # make it the same for kfs

Cryptfile: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

Qroot, Qctl, Qdata: con big iota;	# paths
init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	stderr = sys->fildes(2);

	if (argv != nil)
		argv = tl argv;
	if (len argv != 2)
		exit;
	fd = sys->open(hd argv, Sys->ORDWR);
	key := array[16] of byte;
	for(i := 0; i < 16; i++)
		key[i] = byte (hd tl argv)[i];
	is = keyring->ideasetup(key, nil);

	styx = load Styx Styx->PATH;
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	styxservers->init(styx);
	nametree = load Nametree Nametree->PATH;
	nametree->init();
	sys->pctl(Sys->FORKNS, nil);
	(tree, treeop) := nametree->start();
	tree.create(Qroot, dir(".", 8r555|Sys->DMDIR, Qroot));
	(nil, d) := sys->fstat(fd);
	datad := dir("data", 8r666, Qdata);
	datad.length = d.length;
	tree.create(Qroot, datad);

	(tchan, srv) := Styxserver.new(sys->fildes(0),Navigator.new(treeop), Qroot);
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Read =>
			(fid, err) := srv.canread(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else if(fid.qtype & Sys->QTDIR)
				srv.read(m);
			else{
				count := m.count;
				off := int m.offset;
				error: string = nil;
				ibuf := array[BUFSIZE] of byte;
				buf := array[count] of byte;
				b := buf[0:];
				addr := off % BUFSIZE;
				blk := off / BUFSIZE;
				tot := 0;
				while(count > 0) {
					n := count;
					if(n > (BUFSIZE - addr))
						n = BUFSIZE - addr;
					got := sys->pread(fd, ibuf, BUFSIZE,  big (blk * BUFSIZE));
					if(got == 0) {
						break;
					} else if(got != BUFSIZE) {
						error = "read: incomplete block";
						break;
					}
					keyring->ideaecb(is, ibuf, BUFSIZE, keyring->Decrypt);
					b[0:] = ibuf[addr:addr + n];
					b = b[n:];
					count -= n;
					tot += n;
					blk++;
					addr = 0;
				}
				if(error != nil)
					srv.reply(ref Rmsg.Error(m.tag, error));
				else
					srv.reply(ref Rmsg.Read(m.tag,  buf[0:tot]));
			}
		Write =>
			(nil, err) := srv.canwrite(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else{
				error : string = nil;
				off := int m.offset;
				tot := 0;
				ibuf := array[BUFSIZE] of byte;
				b := m.data[0:];
				addr := off % BUFSIZE;
				blk := off / BUFSIZE;
				count := len m.data;
				while(count > 0) {
					n := count;
					if(n > (BUFSIZE - addr))
						n = BUFSIZE - addr;
					if(addr > 0  || count < BUFSIZE) {
						got := sys->pread(fd, ibuf, BUFSIZE,  big (blk * BUFSIZE));
						if(got == 0)
							;
						else if(got != BUFSIZE) {
							error = "write: incomplete block";
							break;
						}
						keyring->ideaecb(is, ibuf, BUFSIZE, keyring->Decrypt);
						for(i=0; i<n; i++)
							ibuf[addr+i] = b[i];
					} else {
						ibuf[0:] = b[0:n];
					}
					keyring->ideaecb(is, ibuf, BUFSIZE, keyring->Encrypt);
					sys->pwrite(fd, ibuf, BUFSIZE, big (blk * BUFSIZE));
					b = b[n:];
					count -= n;
					tot += n;
					blk++;
					addr = 0;
				}
				if(error != nil)
					srv.reply(ref Rmsg.Error(m.tag, error));
				else
					srv.reply(ref Rmsg.Write(m.tag, tot));
			}
		Open =>
			srv.open(m);
		Stat =>
			srv.stat(m);
		Clunk =>
			srv.clunk(m);
		* =>
			srv.default(gm);
		}
	}
	tree.quit();
}

dir(name: string, perm: int, qid: big): Sys->Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = "cryptfs";
	d.gid = "cryptfs";
	d.qid.path = qid;
	if (perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;
	d.mode = perm;
	return d;
}
