#!/bin/bash

set -e

## Check if we have any configs
if [ -z "$(ls config/*.yaml)" ]; then
	echo "There are no .yaml files in config/, please create them." >&2
	echo "Their name must be the MAC address of eth0, e.g.:" >&2
	echo "  config/dc:a6:32:aa:bb:cc.yaml" >&2
	exit 1
fi

## Check if we have the necessary tools
assert_tool() {
	if [ "x$(which $1)" = "x" ]; then
		echo "Missing required dependency: $1" >&2
		exit 1
	fi
}

assert_tool wget
assert_tool fallocate
assert_tool parted
assert_tool kpartx
assert_tool losetup
assert_tool mkfs.fat
assert_tool mkfs.ext4
assert_tool tune2fs
assert_tool e2label
assert_tool mktemp
assert_tool ar
assert_tool blkid
assert_tool realpath

## Download dependencies
echo "== Checking or downloading dependencies... =="

function dl_dep() {
	if [ ! -f "deps/$1" ]; then
		wget -O deps/$1 $2
	fi
}

mkdir -p deps
dl_dep raspberrypi-firmware.tar.gz https://github.com/raspberrypi/firmware/archive/1.20190925.tar.gz
dl_dep k3os-rootfs-arm64.tar.gz https://github.com/rancher/k3os/releases/download/v0.5.0/k3os-rootfs-arm64.tar.gz

# To find the URL for these packages:
# - Go to https://launchpad.net/ubuntu/bionic/arm64/<package name>/
# - Under 'Publishing history', click the version number in the top row
# - Under 'Downloadable files', use the URL of the .deb file
# - Change http to https

dl_dep libc6-arm64.deb https://launchpadlibrarian.net/365857916/libc6_2.27-3ubuntu1_arm64.deb
dl_dep busybox-arm64.deb https://launchpadlibrarian.net/414117084/busybox_1.27.2-2ubuntu3.2_arm64.deb
dl_dep libcom-err2-arm64.deb https://launchpadlibrarian.net/444344115/libcom-err2_1.44.1-1ubuntu1.2_arm64.deb
dl_dep libblkid1-arm64.deb https://launchpadlibrarian.net/438655401/libblkid1_2.31.1-0.4ubuntu3.4_arm64.deb
dl_dep libuuid1-arm64.deb https://launchpadlibrarian.net/438655406/libuuid1_2.31.1-0.4ubuntu3.4_arm64.deb
dl_dep libext2fs2-arm64.deb https://launchpadlibrarian.net/444344116/libext2fs2_1.44.1-1ubuntu1.2_arm64.deb
dl_dep e2fsprogs-arm64.deb https://launchpadlibrarian.net/444344112/e2fsprogs_1.44.1-1ubuntu1.2_arm64.deb
dl_dep parted-arm64.deb https://launchpadlibrarian.net/415806982/parted_3.2-20ubuntu0.2_arm64.deb
dl_dep libparted2-arm64.deb https://launchpadlibrarian.net/415806981/libparted2_3.2-20ubuntu0.2_arm64.deb
dl_dep libreadline7-arm64.deb https://launchpadlibrarian.net/354246199/libreadline7_7.0-3_arm64.deb
dl_dep libtinfo5-arm64.deb https://launchpadlibrarian.net/371711519/libtinfo5_6.1-1ubuntu1.18.04_arm64.deb
dl_dep libdevmapper1-arm64.deb https://launchpadlibrarian.net/431292125/libdevmapper1.02.1_1.02.145-4.1ubuntu3.18.04.1_arm64.deb
dl_dep libselinux1-arm64.deb https://launchpadlibrarian.net/359065467/libselinux1_2.7-2build2_arm64.deb
dl_dep libudev1-arm64.deb https://launchpadlibrarian.net/444834685/libudev1_237-3ubuntu10.31_arm64.deb
dl_dep libpcre3-arm64.deb https://launchpadlibrarian.net/355683636/libpcre3_8.39-9_arm64.deb
dl_dep util-linux-arm64.deb https://launchpadlibrarian.net/438655410/util-linux_2.31.1-0.4ubuntu3.4_arm64.deb

## Make the image (capacity in MB, not MiB)
echo "== Making image and filesystems... =="
IMAGE=picl-k3os-build.iso
BOOT_CAPACITY=60
# Initial root size. The partition will be resized to the SD card's maximum on first boot.
ROOT_CAPACITY=400
IMAGE_SIZE=$(($BOOT_CAPACITY + $ROOT_CAPACITY))

rm -f $IMAGE
fallocate -l ${IMAGE_SIZE}M $IMAGE
parted -s $IMAGE mklabel msdos
parted -s $IMAGE unit MB mkpart primary fat32 1 $BOOT_CAPACITY
parted -s $IMAGE unit MB mkpart primary $(($BOOT_CAPACITY+1)) $IMAGE_SIZE
parted -s $IMAGE set 1 boot on

## Make the filesystems
LODEV=`sudo losetup --show -f $IMAGE`
sudo kpartx -a $LODEV
sleep 1
LODEV_BOOT=/dev/mapper/`basename ${LODEV}`p1
LODEV_ROOT=/dev/mapper/`basename ${LODEV}`p2
sudo mkfs.fat $LODEV_BOOT
sudo mkfs.ext4 -F $LODEV_ROOT
sudo tune2fs -i 1m $LODEV_ROOT
sudo e2label $LODEV_ROOT "root"

## Mount the filesystems
mkdir boot root
sudo mount $LODEV_BOOT boot
sudo mount $LODEV_ROOT root
sudo mkdir root/bin root/boot root/dev root/etc root/home root/lib root/media
sudo mkdir root/mnt root/opt root/proc root/root root/sbin root/sys
sudo mkdir root/tmp root/usr root/var
sudo chmod 0755 root/*
sudo chmod 0700 root/root
sudo chmod 1777 root/tmp
sudo ln -s /proc/mounts root/etc/mtab
sudo mknod -m 0666 root/dev/null c 1 3

## Unpack root and boot
echo "== Unpacking firmware and rootfs... =="
PITEMP="$(mktemp -d)"
sudo tar -xf deps/raspberrypi-firmware.tar.gz --strip 1 -C $PITEMP
sudo cp -R $PITEMP/boot/* boot
sudo mkdir -p root/lib
sudo cp -R $PITEMP/modules root/lib
sudo rm -rf $PITEMP

## Unpack k3os
sudo tar -xf deps/k3os-rootfs-arm64.tar.gz --strip 1 -C root
# config.yaml will be created by init.resizefs based on MAC of eth0
sudo cp -R config root/k3os/system
K3OS_VERSION=$(ls --indicator-style=none root/k3os/system/k3os | grep -v current | head -n1)

## Set correct kernel, config and cmdline
cat <<EOF | sudo tee boot/config.txt >/dev/null
dtoverlay=vc4-fkms-v3d
gpu_mem=128
arm_64bit=1

[pi3]
audio_pwm_mode=2
[pi4]
max_framebuffers=2
kernel=kernel8.img
[all]
EOF
PARTUUID=$(sudo blkid -o export $LODEV_ROOT | grep PARTUUID)
echo "dwc_otg.lpm_enable=0 root=$PARTUUID rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait init=/sbin/init.resizefs" | sudo tee boot/cmdline.txt >/dev/null

## Install busybox
unpack_deb() {
	ar x deps/$1
	sudo tar -xf data.tar.[gx]z -C $2
	rm -f data.tar.gz data.tar.xz control.tar.gz control.tar.xz debian-binary
}

unpack_deb "libc6-arm64.deb" "root"
unpack_deb "busybox-arm64.deb" "root"

for i in \
	ar \
	awk \
	basename \
	cat \
	chmod \
	dirname \
	dmesg \
	echo \
	fdisk \
	find \
	grep \
	ln \
	ls \
	lsmod \
	mkdir \
	mknod \
	modprobe \
	mount \
	mv \
	poweroff \
	readlink \
	reboot \
	rm \
	rmdir \
	sed \
	sh \
	sleep \
	sync \
	tar \
	touch \
	umount \
	uname \
	wget \
; do
	sudo ln -s busybox root/bin/$i
done

## Add tarball for the libraries and binaries needed to resize root FS
mkdir root-resize
unpack_deb "libcom-err2-arm64.deb" "root-resize"
unpack_deb "libblkid1-arm64.deb" "root-resize"
unpack_deb "libuuid1-arm64.deb" "root-resize"
unpack_deb "libext2fs2-arm64.deb" "root-resize"
unpack_deb "e2fsprogs-arm64.deb" "root-resize"

# TODO: replace parted by fdisk/sfdisk if simpler?
unpack_deb "parted-arm64.deb" "root-resize"
unpack_deb "libparted2-arm64.deb" "root-resize"
unpack_deb "libreadline7-arm64.deb" "root-resize"
unpack_deb "libtinfo5-arm64.deb" "root-resize"
unpack_deb "libdevmapper1-arm64.deb" "root-resize"
unpack_deb "libselinux1-arm64.deb" "root-resize"
unpack_deb "libudev1-arm64.deb" "root-resize"
unpack_deb "libpcre3-arm64.deb" "root-resize"

unpack_deb "util-linux-arm64.deb" "root-resize"
sudo tar -cJf root/root-resize.tar.xz "root-resize"
sudo rm -rf root-resize

## Write a resizing init and an actual init
sudo rm root/sbin/init
sudo install -m 0755 -o root -g root init init.resizefs root/sbin

## Clean up
sync
sudo umount boot
sudo umount root
sleep 1
sudo kpartx -d $LODEV
sleep 1
sudo losetup -d $LODEV
rmdir boot root

IMAGE_FINAL=picl-k3os-${K3OS_VERSION}.img
mv $IMAGE $IMAGE_FINAL
echo ""
echo "== $IMAGE_FINAL created. =="
