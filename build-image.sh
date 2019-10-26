#!/bin/bash

# TODO:
# - resize the root filesystem

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

## Download dependencies
echo "== Checking or downloading dependencies... =="
if [ ! -f "raspberrypi-firmware.tar.gz" ]; then
	wget -O raspberrypi-firmware.tar.gz https://github.com/raspberrypi/firmware/archive/1.20190925.tar.gz
fi

if [ ! -f "k3os-rootfs-arm64.tar.gz" ]; then
	wget https://github.com/rancher/k3os/releases/download/v0.5.0/k3os-rootfs-arm64.tar.gz
fi

## Make the image (capacity in MB, not MiB)
echo "== Making image and filesystems... =="
IMAGE=picl-k3os-build.iso
BOOT_CAPACITY=200
# Initial root size. The partition will be resized to the SD card's maximum on first boot.
ROOT_CAPACITY=500
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

## Unpack raspberry pi firmware
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
echo "dwc_otg.lpm_enable=0 root=$PARTUUID rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait" | sudo tee boot/cmdline.txt >/dev/null

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
