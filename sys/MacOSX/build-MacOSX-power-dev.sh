#!/dis/sh.dis
load std

cd /sys #/emu/MacOSX
cp win.c win.c.bak
run /sys/MacOSX/power/profile
#mk nuke
mk install #&& os open $ghome/Documents/AcmeSAC/Package/AcmeSAC.app
#&& mk clean
rm -rf /tmp/*
