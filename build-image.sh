#!/bin/bash

set -e

## Check if we have the config.yaml
if [ ! -e "config.yaml" ]; then
	echo "config.yaml is missing, please create it" >&2
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
if [ ! -f "raspberrypi-firmware.tar.gz" ]; then
	wget -O raspberrypi-firmware.tar.gz https://github.com/raspberrypi/firmware/archive/1.20190925.tar.gz
fi

if [ ! -f "k3os-rootfs-arm64.tar.gz" ]; then
	wget https://github.com/rancher/k3os/releases/download/v0.5.0/k3os-rootfs-arm64.tar.gz
fi

# To find the URL for these packages:
# - Go to https://launchpad.net/ubuntu/bionic/arm64/<package name>/
# - Under 'Publishing history', click the version number in the top row
# - Under 'Downloadable files', use the URL of the .deb file
# - Change http to https
# - Use wget -O to save the file to a filename without a version number

if [ ! -f "libc6-arm64.deb" ]; then
	wget -O libc6-arm64.deb https://launchpadlibrarian.net/365857916/libc6_2.27-3ubuntu1_arm64.deb
fi
if [ ! -f "busybox-arm64.deb" ]; then
	wget -O busybox-arm64.deb https://launchpadlibrarian.net/414117084/busybox_1.27.2-2ubuntu3.2_arm64.deb
fi
if [ ! -f "libcom-err2-arm64.deb" ]; then
	wget -O libcom-err2-arm64.deb https://launchpadlibrarian.net/444344115/libcom-err2_1.44.1-1ubuntu1.2_arm64.deb
fi
if [ ! -f "libblkid1-arm64.deb" ]; then
	wget -O libblkid1-arm64.deb https://launchpadlibrarian.net/438655401/libblkid1_2.31.1-0.4ubuntu3.4_arm64.deb
fi
if [ ! -f "libuuid1-arm64.deb" ]; then
	wget -O libuuid1-arm64.deb https://launchpadlibrarian.net/438655406/libuuid1_2.31.1-0.4ubuntu3.4_arm64.deb
fi
if [ ! -f "libext2fs2-arm64.deb" ]; then
	wget -O libext2fs2-arm64.deb https://launchpadlibrarian.net/444344116/libext2fs2_1.44.1-1ubuntu1.2_arm64.deb
fi
if [ ! -f "e2fsprogs-arm64.deb" ]; then
	wget -O e2fsprogs-arm64.deb https://launchpadlibrarian.net/444344112/e2fsprogs_1.44.1-1ubuntu1.2_arm64.deb
fi
if [ ! -f "parted-arm64.deb" ]; then
	wget -O parted-arm64.deb https://launchpadlibrarian.net/415806982/parted_3.2-20ubuntu0.2_arm64.deb
fi
if [ ! -f "libparted2-arm64.deb" ]; then
	wget -O libparted2-arm64.deb https://launchpadlibrarian.net/415806981/libparted2_3.2-20ubuntu0.2_arm64.deb
fi
if [ ! -f "libreadline7-arm64.deb" ]; then
	wget -O libreadline7-arm64.deb https://launchpadlibrarian.net/354246199/libreadline7_7.0-3_arm64.deb
fi
if [ ! -f "libtinfo5-arm64.deb" ]; then
	wget -O libtinfo5-arm64.deb https://launchpadlibrarian.net/371711519/libtinfo5_6.1-1ubuntu1.18.04_arm64.deb
fi
if [ ! -f "libdevmapper1-arm64.deb" ]; then
	wget -O libdevmapper1-arm64.deb https://launchpadlibrarian.net/431292125/libdevmapper1.02.1_1.02.145-4.1ubuntu3.18.04.1_arm64.deb
fi
if [ ! -f "libselinux1-arm64.deb" ]; then
	wget -O libselinux1-arm64.deb https://launchpadlibrarian.net/359065467/libselinux1_2.7-2build2_arm64.deb
fi
if [ ! -f "libudev1-arm64.deb" ]; then
	wget -O libudev1-arm64.deb https://launchpadlibrarian.net/444834685/libudev1_237-3ubuntu10.31_arm64.deb
fi
if [ ! -f "libpcre3-arm64.deb" ]; then
	wget -O libpcre3-arm64.deb https://launchpadlibrarian.net/355683636/libpcre3_8.39-9_arm64.deb
fi
if [ ! -f "util-linux-arm64.deb" ]; then
	wget -O util-linux-arm64.deb https://launchpadlibrarian.net/438655410/util-linux_2.31.1-0.4ubuntu3.4_arm64.deb
fi

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
sudo tar -xf raspberrypi-firmware.tar.gz --strip 1 -C $PITEMP
sudo cp -R $PITEMP/boot/* boot
sudo mkdir -p root/lib
sudo cp -R $PITEMP/modules root/lib
sudo rm -rf $PITEMP

## Unpack k3os
sudo tar -xf k3os-rootfs-arm64.tar.gz --strip 1 -C root
sudo cp config.yaml root/k3os/system
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
	ar x $1
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
cat <<EOF | sudo tee root/sbin/init.resizefs >/dev/null
#!/bin/sh

# sleep a second for devices to settle
sleep 1

mount -t proc none /proc
mount -t sysfs none /sys

# Unpack tools for resizing root FS
mount -t tmpfs -o size=50m none /tmp
tar -xJf /root-resize.tar.xz --strip 1 -C /tmp

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/tmp/sbin:/tmp/bin:/tmp/usr/sbin:/tmp/usr/bin
export LD_LIBRARY_PATH=/tmp/lib:/tmp/lib/aarch64-linux-gnu:/tmp/usr/lib:/tmp/usr/lib/aarch64-linux-gnu

PARTUUID=\$(cat /proc/cmdline | sed -r 's/^.*PARTUUID=([^ ]+).*$/\1/')
ROOTDEVICE=\$(blkid | grep PARTUUID=\\"\$PARTUUID\\" | awk -F: '{print \$1}')
ROOTDISK=/dev/\$(basename \$(dirname \$(readlink /sys/class/block/\$(basename \$ROOTDEVICE))))

echo "== Performing filesystem check on root device \$ROOTDEVICE... =="
e2fsck -pv \$ROOTDEVICE
sleep 5
echo "== Resizing root filesystem on \$ROOTDISK... =="
parted -s \$ROOTDISK resizepart 2 100%
mount -o remount,rw /
resize2fs \$ROOTDEVICE
sleep 5

echo "== Setting proper init... =="
mount \${ROOTDISK}p1 /boot
sed -i 's# init=/sbin/init.resizefs##' /boot/cmdline.txt
# TODO: update partuuid? does not seem to be necessary?
umount /boot

echo "== Cleaning up and rebooting... =="
rm /root-resize.tar.xz
rm /sbin/init.resizefs
sync
mount -o remount,ro /
sleep 5
reboot -f
EOF
sudo chmod +x root/sbin/init.resizefs

sudo rm root/sbin/init
cat <<EOF | sudo tee root/sbin/init >/dev/null
#!/bin/sh
modprobe squashfs
exec /sbin/k3os
EOF
sudo chmod +x root/sbin/init

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
