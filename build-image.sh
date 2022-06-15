#!/bin/bash

set -e


# Set this to default to a KNOWN GOOD pi firmware (e.g. 1.20200811); this is used if RASPBERRY_PI_FIRMWARE env variable is not specified
DEFAULT_GOOD_PI_VERSION="1.20200811"

# Set this to default to a KNOWN GOOD k3os (e.g. v0.11.0); this is used if K3OS_VERSION env variable is not specified
DEFAULT_GOOD_K3OS_VERSION="v0.11.0"

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

get_pifirmware() {
    #  Uses RASPBERRY_PI_FIRMWARE env variable to allow the user to control which pi firmware version to use.
    # - 1. unset, in which case it is initialized to a known good version (DEFAULT_GOOD_PI_VERSION)
    # - 2. set to "latest" in which case it pulls the latest firmware from git repo.
    # - 3. set by the user to desired version

    if [ -z "${RASPBERRY_PI_FIRMWARE}" ]; then
        echo "RASPBERRY_PI_FIRMWARE env variable was not set - defaulting to known good firmware [${DEFAULT_GOOD_PI_VERSION}]"
        dl_dep raspberrypi-firmware.tar.gz https://github.com/raspberrypi/firmware/archive/"${DEFAULT_GOOD_PI_VERSION}".tar.gz
    elif [ "${RASPBERRY_PI_FIRMWARE}" = "latest" ]; then
        echo "RASPBERRY_PI_FIRMWARE env variable set to 'latest' - using latest pi firmware release"
        dl_dep raspberrypi-firmware.tar.gz "$(wget -qO - https://api.github.com/repos/raspberrypi/firmware/tags | jq -r '.[0].tarball_url')"
    else
        # set to requested version, but first check if it is a valid version
        for i in $(wget -qO - https://api.github.com/repos/raspberrypi/firmware/tags | jq  --arg RASPBERRY_PI_FIRMWARE "${RASPBERRY_PI_FIRMWARE}" -r '.[].tarball_url | contains($RASPBERRY_PI_FIRMWARE)')
        do
            if [ "$i" = "true" ]; then FOUND=true; break; fi
        done
        if [ "${FOUND}" = true ]; then
            echo "RASPBERRY_PI_FIRMWARE env variable set to [${RASPBERRY_PI_FIRMWARE}] - will use this firmware."
            dl_dep raspberrypi-firmware.tar.gz https://github.com/raspberrypi/firmware/archive/"${RASPBERRY_PI_FIRMWARE}".tar.gz
        else
            echo "Requested raspberry pi firmware [${RASPBERRY_PI_FIRMWARE}] is not valid (does not exist in pi firmware repo)! Exiting Build!"
            exit 1;
        fi
    fi
}

assert_tool wget
assert_tool mktemp
assert_tool truncate
assert_tool parted
assert_tool partprobe
assert_tool losetup
assert_tool mkfs.fat
assert_tool mkfs.ext4
assert_tool tune2fs
assert_tool e2label
assert_tool mktemp
assert_tool ar
assert_tool blkid
assert_tool 7z
assert_tool dd
assert_tool jq

## Check if we are building a supported image
IMAGE_TYPE=$1

if [ -z "$IMAGE_TYPE" -o "$IMAGE_TYPE" = "help" -o "$IMAGE_TYPE" = "--help" -o "$IMAGE_TYPE" = "-h" ]; then
	echo "Usage: $0 <image type>" >&2
	echo "Supported image types:" >&2
	echo "  raspberrypi - Raspberry Pi model 3B+/4." >&2
	echo "  orangepipc2 - Orange Pi PC 2" >&2
	echo "  all         - Calls itself once for each supported image type" >&2
	exit 1
elif [ "$IMAGE_TYPE" = "raspberrypi" ]; then
	echo "Building an image for the Raspberry Pi model 3B+/4."
elif [ "$IMAGE_TYPE" = "orangepipc2" ]; then
	echo "Building an image for the Orange Pi PC 2."
elif [ "$IMAGE_TYPE" = "all" ]; then
	$0 "raspberrypi"
	$0 "orangepipc2"
	exit 0
else
	echo "Unsupported image type \"$IMAGE_TYPE\". See \"$0 help\" for more information." >&2
	exit 1
fi

if [ "$IMAGE_TYPE" = "orangepipc2" ]; then
	# mkimage is in u-boot-tools
	assert_tool mkimage
fi

## Download dependencies
echo "== Checking or downloading dependencies... =="

function dl_dep() {
	if [ ! -f "deps/$1" ]; then
		wget -O deps/$1 $2
	fi
}

mkdir -p deps

if [ "$IMAGE_TYPE" = "raspberrypi" ]; then
	get_pifirmware
elif [ "$IMAGE_TYPE" = "orangepipc2" ]; then
	# TODO: apt.armbian.com removes old versions, so these URLs become
	# outdated. Find an armbian mirror that keeps old versions so that
	# the URLs remain functional.
	dl_dep linux-dtb-dev-sunxi64.deb https://apt.armbian.com/pool/main/l/linux-5.4.2-sunxi64/linux-dtb-dev-sunxi64_19.11.3.348_arm64.deb
	dl_dep linux-image-dev-sunxi64.deb https://apt.armbian.com/pool/main/l/linux-5.4.2-sunxi64/linux-image-dev-sunxi64_19.11.3.348_arm64.deb

	if [ ! -f "deps/armbian_orangepipc2.img" ]; then
		pushd deps
		wget -O Armbian_orangepipc2_buster_current.7z https://dl.armbian.com/orangepipc2/archive/Armbian_19.11.3_Orangepipc2_buster_current_5.3.9.7z
		7z x Armbian_orangepipc2_buster_current.7z \*.img
		dd of=armbian_orangepipc2.img bs=1024 count=4096 < Armbian_*_Orangepipc2_buster_current_*.img
		rm Armbian_*_Orangepipc2_buster_current_*.img Armbian_orangepipc2_buster_current.7z
		popd
	fi
fi

if [ -z "${K3OS_VERSION}" ]; then
    echo "K3OS_VERSION env variable was not set - defaulting to known version [${DEFAULT_GOOD_K3OS_VERSION}]"
    dl_dep k3os-rootfs-arm64.tar.gz https://github.com/rancher/k3os/releases/download/${DEFAULT_GOOD_K3OS_VERSION}/k3os-rootfs-arm64.tar.gz
elif [ "${K3OS_VERSION}" = "latest" ]; then
    echo "K3OS_VERSION env variable set to 'latest' - using latest release"
    dl_dep k3os-rootfs-arm64.tar.gz "$(wget -qO - https://api.github.com/repos/rancher/k3os/releases/latest | jq -r '.assets[] | select(.name == "k3os-rootfs-arm64.tar.gz") .browser_download_url')"
else
    echo "K3OS_VERSION env variable set to ${K3OS_VERSION}"
    dl_dep k3os-rootfs-arm64.tar.gz https://github.com/rancher/k3os/releases/download/${K3OS_VERSION}/k3os-rootfs-arm64.tar.gz
fi

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
dl_dep rpi-firmware-nonfree-buster.zip https://github.com/RPi-Distro/firmware-nonfree/archive/buster.zip

## Make the image (capacity in MB, not MiB)
echo "== Making image and filesystems... =="
IMAGE=$(mktemp picl-k3os-build.iso.XXXXXX)

if [ "$IMAGE_TYPE" = "raspberrypi" ]; then
	# Create two partitions: boot and root.
	BOOT_CAPACITY=60
	# Initial root size. The partition will be resized to the SD card's maximum on first boot.
	ROOT_CAPACITY=1000
	IMAGE_SIZE=$(($BOOT_CAPACITY + $ROOT_CAPACITY))

	truncate -s ${IMAGE_SIZE}M $IMAGE
	parted -s $IMAGE mklabel msdos
	parted -s $IMAGE unit MB mkpart primary fat32 1 $BOOT_CAPACITY
	parted -s $IMAGE unit MB mkpart primary $(($BOOT_CAPACITY+1)) $IMAGE_SIZE
	parted -s $IMAGE set 1 boot on
elif [ "$IMAGE_TYPE" = "orangepipc2" ]; then
	# Create a single partition; bootloader is copied from armbian
	# at specific locations before the first partition. The partition
	# will be resized to the SD card's maximum on first boot.
	truncate -s 600M $IMAGE
	parted -s $IMAGE mklabel msdos
	parted -s $IMAGE unit s mkpart primary 8192 100%

	# copy everything before the first partition, except the partition table
	dd if=deps/armbian_orangepipc2.img of=$IMAGE bs=512 skip=1 seek=1 count=8191 conv=notrunc
fi

LODEV=`sudo losetup --show -P -f $IMAGE`
sudo partprobe -s $LODEV
sleep 1

if [ "$IMAGE_TYPE" = "raspberrypi" ]; then
	LODEV_BOOT=${LODEV}p1
	LODEV_ROOT=${LODEV}p2
	sudo mkfs.fat $LODEV_BOOT
elif [ "$IMAGE_TYPE" = "orangepipc2" ]; then
	LODEV_ROOT=${LODEV}p1
fi

sudo mkfs.ext4 -F $LODEV_ROOT
sudo tune2fs -i 1m $LODEV_ROOT
sudo e2label $LODEV_ROOT "root"

## Initialize root
echo "== Initializing root... =="
mkdir root
sudo mount $LODEV_ROOT root
sudo mkdir root/bin root/boot root/dev root/etc root/home root/lib root/media
sudo mkdir root/mnt root/opt root/proc root/root root/sbin root/sys
sudo mkdir root/tmp root/usr root/var
sudo chmod 0755 root/*
sudo chmod 0700 root/root
sudo chmod 1777 root/tmp
sudo ln -s /proc/mounts root/etc/mtab
sudo mknod -m 0666 root/dev/null c 1 3

## Initialize boot
echo "== Initializing boot... =="
if [ "$IMAGE_TYPE" = "raspberrypi" ]; then
	PITEMP="$(mktemp -d)"
	sudo tar -xf deps/raspberrypi-firmware.tar.gz --strip 1 -C $PITEMP

	mkdir boot
	sudo mount $LODEV_BOOT boot
	sudo cp -R $PITEMP/boot/* boot
	sudo cp -R $PITEMP/modules root/lib

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
	QUIRKS=$( [ -f quirks.txt ] && cat quirks.txt || true)
	echo "dwc_otg.lpm_enable=0 root=$PARTUUID rootfstype=ext4 cgroup_memory=1 cgroup_enable=memory rootwait init=/sbin/init.resizefs ro $QUIRKS" | sudo tee boot/cmdline.txt >/dev/null
	sudo rm -rf $PITEMP
elif [ "$IMAGE_TYPE" = "orangepipc2" ]; then
	cat <<EOF | sudo tee root/boot/env.txt >/dev/null
extraargs=rootwait init=/sbin/init.resizefs ro
EOF
	sudo install -m 0644 -o root -g root orangepipc2-boot.cmd root/boot/boot.cmd
	sudo mkimage -C none -A arm -T script -d root/boot/boot.cmd root/boot/boot.scr
fi

## Install k3os, busybox and resize dependencies
echo "== Installing... =="
sudo tar -xf deps/k3os-rootfs-arm64.tar.gz --strip 1 -C root
# config.yaml will be created by init.resizefs based on MAC of eth0
sudo cp -R config root/k3os/system
for filename in root/k3os/system/config/*.*; do [ "$filename" != "${filename,,}" ] && sudo mv "$filename" "${filename,,}" ; done 
K3OS_VERSION=$(ls --indicator-style=none root/k3os/system/k3os | grep -v current | head -n1)

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
	tail \
	tar \
	touch \
	umount \
	uname \
	wget \
; do
	sudo ln -s busybox root/bin/$i
done

if [ "$IMAGE_TYPE" = "orangepipc2" ]; then
	unpack_deb "linux-dtb-dev-sunxi64.deb" "root"
	sudo ln -s $(cd root/boot; ls -d dtb-*-sunxi64 | head -n1) root/boot/dtb
	unpack_deb "linux-image-dev-sunxi64.deb" "root"
	sudo ln -s $(cd root/boot; ls -d vmlinuz-*-sunxi64 | head -n1) root/boot/Image
elif [ "$IMAGE_TYPE" = "raspberrypi" ]; then
  BRCMTMP=$(mktemp -d)
  7z e -y deps/rpi-firmware-nonfree-buster.zip -o"$BRCMTMP" "firmware-nonfree-buster/brcm/*" > /dev/null
  sudo mkdir -p root/lib/firmware/brcm/
  sudo cp "$BRCMTMP"/brcmfmac43455* root/lib/firmware/brcm/
  sudo cp "$BRCMTMP"/brcmfmac43430* root/lib/firmware/brcm/
  rm -rf "$BRCMTMP"
fi

## Add libraries and binaries needed to resize root FS & fsck every boot
unpack_deb "libcom-err2-arm64.deb" "root"
unpack_deb "libblkid1-arm64.deb" "root"
unpack_deb "libuuid1-arm64.deb" "root"
unpack_deb "libext2fs2-arm64.deb" "root"
unpack_deb "e2fsprogs-arm64.deb" "root"
unpack_deb "util-linux-arm64.deb" "root"

## Add tarball for the libraries and binaries needed only to resize root FS
# TODO: replace parted by fdisk/sfdisk if simpler?
mkdir root-resize
unpack_deb "parted-arm64.deb" "root-resize"
unpack_deb "libparted2-arm64.deb" "root-resize"
unpack_deb "libreadline7-arm64.deb" "root-resize"
unpack_deb "libtinfo5-arm64.deb" "root-resize"
unpack_deb "libdevmapper1-arm64.deb" "root-resize"
unpack_deb "libselinux1-arm64.deb" "root-resize"
unpack_deb "libudev1-arm64.deb" "root-resize"
unpack_deb "libpcre3-arm64.deb" "root-resize"

sudo tar -cJf root/root-resize.tar.xz "root-resize"
sudo rm -rf root-resize

## Write a resizing init and a pre-init
sudo install -m 0755 -o root -g root init.preinit init.resizefs root/sbin
sudo sed -i "s#@IMAGE_TYPE@#$IMAGE_TYPE#" root/sbin/init.resizefs root/sbin/init.preinit

## Clean up
sync
if [ "$IMAGE_TYPE" = "raspberrypi" ]; then
	sudo umount boot
	rmdir boot
fi
sudo umount root
rmdir root
sync
sleep 1
sudo losetup -d $LODEV

IMAGE_FINAL=picl-k3os-${K3OS_VERSION}-${IMAGE_TYPE}.img
mv $IMAGE $IMAGE_FINAL
echo ""
echo "== $IMAGE_FINAL created. =="
