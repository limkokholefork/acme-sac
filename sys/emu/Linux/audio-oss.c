#include "dat.h"
#include "fns.h"
#include "error.h"
#include "audio.h"
#include <sys/ioctl.h>
#include <sys/soundcard.h>

#define 	Audio_Mic_Val		SOUND_MIXER_MIC
#define 	Audio_Linein_Val	SOUND_MIXER_LINE

#define		Audio_Speaker_Val	SOUND_MIXER_PCM // SOUND_MIXER_VOLUME
#define		Audio_Headphone_Val	SOUND_MIXER_ALTPCM
#define		Audio_Lineout_Val	SOUND_MIXER_CD

#define 	Audio_Pcm_Val		AFMT_S16_LE
#define 	Audio_Ulaw_Val		AFMT_MU_LAW
#define 	Audio_Alaw_Val		AFMT_A_LAW

#include "audio-tbls.c"
#define	min(a,b)	((a) < (b) ? (a) : (b))

#define DEVAUDIO	"/dev/dsp"
#define DEVMIXER	"/dev/mixer"

#define DPRINT if(0)print

static struct Audio_fd {
	int data;	/* dsp data fd */
	int ctl;	/* mixer fd */
} afd = {-1, -1};

enum {
	A_Pause,
	A_UnPause,
	A_In,
	A_Out,
};

static Audio_t av;
static QLock inlock;
static QLock outlock;

static int audio_open(int omode);
static int audio_pause(int fd, int f);

Audio_t*
getaudiodev(void)
{
	return &av;
}

void 
audio_file_init ()
{
	DPRINT("audio_file_init %d %d\n", afd.data, afd.ctl);
	afd.ctl = -1;
	afd.ctl = open(DEVMIXER, ORDWR);
	if(afd.ctl < 0){
		// oserror() produces a sigsegv in arm
		DPRINT("can't open mixer device: %s\n", strerror(errno));
		close(afd.ctl);
		afd.ctl = -1;
	}
	
	audio_info_init(&av);
}

void
audio_file_open(Chan *c, int omode)
{
	DPRINT("audio_file_open %d %d %x\n", afd.data, afd.ctl, omode);
	switch(omode){
	case OREAD:
		qlock(&inlock);
		if(waserror()){
			qunlock(&inlock);
			nexterror();
		}

		if(afd.data >= 0)
			error(Einuse);
		if((afd.data = audio_open(omode)) < 0)
			oserror();

		poperror();
		qunlock(&inlock);
		break;
	case OWRITE:
		qlock(&outlock);
		if(waserror()){
			qunlock(&outlock);
			nexterror();
		}
		if(afd.data >= 0)
			error(Einuse);
		if((afd.data = audio_open(omode)) < 0)
			oserror();
		
		poperror();
		qunlock(&outlock);
		break;
	case ORDWR:
		qlock(&inlock);
		qlock(&outlock);
		if(waserror()){
			qunlock(&inlock);
			qunlock(&outlock);
			nexterror();
		}

		if(afd.data >= 0)
			error(Einuse);
		if((afd.data = audio_open(omode)) < 0)
			oserror();
		if(waserror()){
			close(afd.data);
			afd.data = -1;
			nexterror();
		}

		poperror();
		qunlock(&inlock);
		qunlock(&outlock);
		break;
	}
}

void    
audio_file_close(Chan *c)
{
	DPRINT("audio_file_close %d %d\n", afd.data, afd.ctl);
	switch(c->mode){
	case OREAD:
		qlock(&inlock);
		close (afd.data);
		afd.data = -1;
		qunlock(&inlock);
		break;
	case OWRITE:
		qlock(&outlock);
		close(afd.data);
		afd.data = -1;
		qunlock(&outlock);
		break;
	case ORDWR:
		qlock(&inlock);
		qlock(&outlock);
		close(afd.data);
		afd.data = -1;
		qunlock(&inlock);
		qunlock(&outlock);
		break;
	}

}

long
audio_file_read(Chan *c, void *va, long count, vlong offset)
{
	long ba, status, chunk, total;

	DPRINT("audio_file_read %d %d\n", afd.data, afd.ctl);
	qlock(&inlock);
	if(waserror()){
		qunlock(&inlock);
		nexterror();
	}

	if(afd.data < 0)
		error(Eperm);

	/* check block alignment */
	ba = av.in.bits * av.in.chan / Bits_Per_Byte;

	if(count % ba)
		error(Ebadarg);
		
	if(!audio_pause(afd.data, A_UnPause))
		error(Eio);
	
	total = 0;
	while (total < count) {
		chunk = count - total;
		status = read (afd.data, va + total, chunk);
		if (status < 0)
			error(Eio);
		total += status;
	}
	
	if (total != count)
		error(Eio);

	poperror();
	qunlock(&inlock);
	
	return count;
}

long                                            
audio_file_write(Chan *c, void *va, long count, vlong offset)
{
	long status = -1;
	long ba, total, chunk, bufsz;
	
	DPRINT("audio_file_write %d %d\n", afd.data, afd.ctl);
	qlock(&outlock);
	if(waserror()){
		qunlock(&outlock);
		nexterror();
	}
	
	if(afd.data < 0)
		error(Eperm);
	
	/* check block alignment */
	ba = av.out.bits * av.out.chan / Bits_Per_Byte;

	if(count % ba)
		error(Ebadarg);

	total = 0;
	bufsz = av.out.buf * Audio_Max_Buf / Audio_Max_Val;

	if(bufsz == 0)
		error(Ebadarg);

	while(total < count) {
		chunk = min(bufsz, count - total);
		status = write(afd.data, va, chunk);
		if(status <= 0)
			error(Eio);
		total += status;
	}

	poperror();
	qunlock(&outlock);

	return count;	
}

long
audio_ctl_write(Chan *c, void *va, long count, vlong offset)
{
	Audio_t tmpav = av;
	int force_open = 0;

	tmpav.in.flags = 0;
	tmpav.out.flags = 0;
	
	DPRINT ("audio_ctl_write %X %X\n", afd.data, afd.ctl);
	if (!audioparse(va, count, &tmpav))
		error(Ebadarg);

	qlock(&inlock);
	if (waserror()){
		qunlock(&inlock);
		nexterror();
	}

	/* afd needs to be opened to issue a write to /dev/audioctl */
	if (afd.data == -1){
		force_open=1;
		afd.data = open(DEVAUDIO, O_RDONLY|O_NONBLOCK);
	}

	if (afd.data < 0)
		error(Ebadarg);

	if (tmpav.in.flags & AUDIO_MOD_FLAG) {
		if (!audio_pause(afd.data, A_Pause))
			error(Ebadarg);
		if (!audio_set_info(afd.data, &tmpav.in, A_In))
			error(Ebadarg);
	}
	poperror();
	qunlock(&inlock);

	tmpav.in.flags = 0;
	
	av = tmpav;
	if (force_open) {
		close(afd.data);
		afd.data = -1;
	}
	return count;
}

/* Linux/OSS specific stuff */

static int
choosefmt(Audio_d *i)
{
	int newbits, newenc;
	
	newbits = i->bits;
	newenc = i->enc;
	switch (newenc) {
	case Audio_Alaw_Val:
		if (newbits == 8)
			return AFMT_A_LAW;
		break;
	case Audio_Ulaw_Val:
		if (newbits == 8)
			return AFMT_MU_LAW;
		break;
	case Audio_Pcm_Val:
		if (newbits == 8)
			return AFMT_U8;
		else if (newbits == 16)
			return AFMT_S16_LE;
		break;
	}
	return -1;
}

static int
setvolume(int fd, int what, int left, int right)
{
	int can, v;
	
	if(fd < 0)
		error("audio device not open");

	if(ioctl(fd, SOUND_MIXER_READ_DEVMASK, &can) < 0)
		can = ~0;

	DPRINT("setvolume fd%d %X can mix 0x%X (mask %X)\n", fd, what, (can & (1<<what)), can);
	if(!(can & (1<<what)))
		return 0;
	v = left | (right<<8);
	if(ioctl(afd.ctl, MIXER_WRITE(what), &v) < 0)
		oserror();
}

int
audio_set_info(int fd, Audio_d *i, int d)
{
	int status, arg;
	int oldfmt, newfmt;
	
	DPRINT("audio_set_info (%d) %d %d\n", fd, afd.data, afd.ctl);
	if (fd < 0)
		return 0;

	/* sample rate */
	if (i->flags & AUDIO_RATE_FLAG){
		arg = i->rate;
		if(ioctl(fd, SNDCTL_DSP_SPEED, &arg) < 0)
			return 0;
	}
	
	/* channels */
	if(i->flags & AUDIO_CHAN_FLAG){
		arg = i->chan;
		if(ioctl(fd, SNDCTL_DSP_CHANNELS, &arg) < 0)
			return 0;
	}

	/* precision */
	if(i->flags & AUDIO_BITS_FLAG){
		arg = i->bits;
		if(ioctl(fd, SNDCTL_DSP_SAMPLESIZE, &arg) < 0)
			return 0;
	}
	
	/* encoding */
	if(i->flags & AUDIO_ENC_FLAG){
		ioctl(fd, SNDCTL_DSP_GETFMTS, &oldfmt);

		newfmt = choosefmt(i);
		if(newfmt != oldfmt){
			status = ioctl(fd, SNDCTL_DSP_SETFMT, &arg);
			DPRINT ("enc oldfmt newfmt %x status %d\n", oldfmt, newfmt, status);
		}
	}

	/* dev volume */ 
	if(i->flags & (AUDIO_LEFT_FLAG|AUDIO_VOL_FLAG))
		setvolume(afd.ctl, i->dev, i->left, i->right);

	return 1;
}

static int
audio_set_blocking(int fd)
{
	int val;

	if((val = fcntl(fd, F_GETFL, 0)) == -1)
		return 0;
	
	val &= ~O_NONBLOCK;

	if(fcntl(fd, F_SETFL, val) < 0)
		return 0;

	return 1;
}

static int
audio_open (int omode)
{
	int fd, val;
	
	/* open non-blocking in case someone already has it open */
	/* otherwise we would block until they close! */
	switch (omode){
	case OREAD:
		fd = open(DEVAUDIO, O_RDONLY|O_NONBLOCK);
		break;
	case OWRITE:
		fd = open(DEVAUDIO, O_WRONLY|O_NONBLOCK);
		break;
	case ORDWR:
		fd = open(DEVAUDIO, O_RDWR|O_NONBLOCK);
		break;
	}

	DPRINT("audio_open %d\n", fd);
	if(fd < 0)
		oserror();

	/* change device to be blocking */
	if(!audio_set_blocking(fd)) {
		close(fd);
		error("cannot set blocking mode");
	}

	if(!audio_pause(fd, A_Pause)) {
		close(fd);
		error(Eio);
	}

	/* set audio info */
	av.in.flags = ~0;
	av.out.flags = ~0;

	if(!audio_set_info(fd, &av.in, A_In)) {
		close(fd);
		error(Ebadarg);
	}

	av.in.flags = 0;

	/* tada, we're open, blocking, paused and flushed */
	return fd;
}

static int
audio_pause(int fd, int f)
{
	int status;
	static int	audio_in_pause = A_UnPause;

//	DPRINT ("audio_pause (%d) %d %d\n", fd, afd.data, afd.ctl);
	if (fd < 0)
		return 0;
	
	if (fd == afd.data && audio_in_pause == f)
		return 1;

	status = ioctl(fd, SNDCTL_DSP_RESET, NULL);
	if (status < 0)
		return 0;
	status = ioctl(fd, SNDCTL_DSP_SYNC, NULL);
	audio_in_pause = f;
	
	return 1;
}
