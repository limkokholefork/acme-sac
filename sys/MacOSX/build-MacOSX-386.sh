#!/dis/sh.dis
load std

cd /sys
run /sys/MacOSX/386/profile
mk nuke
mk install && mk clean
rm -rf /tmp/*
