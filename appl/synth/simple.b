
instrument(nil: Source, c: Sample, ctl: Control)
{
	wave := array[1] of {Inst.mk(nil, waveloop)};

	adsri := Inst.mk(wave, adsr);
	adsri.ctl <-= (CATTACK, 0.01);
	adsri.ctl <-= (CDECAY, 0.11);
	adsri.ctl <-= (CSUSTAIN, 0.3);
	adsri.ctl <-= (CRELEASE, 0.001);


	for(;;) alt{
	(a, rc) := <-c =>
		adsri.c <-= (a, rc);
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			adsri.ctl <-= (m, n);
			wave[0].ctl <-= (CFREQ, n);
		CKEYOFF =>
			adsri.ctl <-= (m, n);
		}
	}
}
