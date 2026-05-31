set -ex
wget -O ice-1.13.7.tar.gz "https://sourceforge.net/projects/e1000/files/ice%20stable/1.13.7/ice-1.13.7.tar.gz/download"
tar -xf ice-1.13.7.tar.gz
cd ice-1.13.7/src/
make install > makelog 2>&1
cd ..
mkdir -p /lib/firmware/updates/intel/ice/ddp/
cp ddp/ice-1.3.35.0.pkg /lib/firmware/updates/intel/ice/ddp/
modprobe -r ice
modprobe ice
