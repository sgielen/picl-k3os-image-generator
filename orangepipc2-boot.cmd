setenv load_addr "0x44000000"
setenv rootdev "/dev/mmcblk0p1"
setenv verbosity "1"
setenv rootfstype "ext4"
setenv overlay_prefix "sun50i-h5"

if test -e ${devtype} ${devnum} ${prefix}env.txt; then
	load ${devtype} ${devnum} ${load_addr} ${prefix}env.txt
	env import -t ${load_addr} ${filesize}
fi

setenv consoleargs "console=ttyS0,115200 console=tty1"
if test "${devtype}" = "mmc"; then part uuid mmc 0:1 partuuid; fi

setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} ${consoleargs} panic=10 consoleblank=0 loglevel=${verbosity} ubootpart=${partuuid} usb-storage.quirks=${usbstoragequirks} cgroup_enable=memory swapaccount=1 ${extraargs} ${extraboardargs}"

load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}dtb/${fdtfile}
fdt addr ${fdt_addr_r}
fdt resize 65536
for overlay_file in ${overlays}; do
	if load ${devtype} ${devnum} ${load_addr} ${prefix}dtb/allwinner/overlay/${overlay_prefix}-${overlay_file}.dtbo; then
		echo "Applying kernel provided DT overlay ${overlay_prefix}-${overlay_file}.dtbo"
		fdt apply ${load_addr} || setenv overlay_error "true"
	fi
done
if test "${overlay_error}" = "true"; then
	echo "Error applying DT overlays, restoring original DT"
	load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}dtb/${fdtfile}
else
	if load ${devtype} ${devnum} ${load_addr} ${prefix}dtb/allwinner/overlay/${overlay_prefix}-fixup.scr; then
		echo "Applying kernel provided DT fixup script (${overlay_prefix}-fixup.scr)"
		source ${load_addr}
	fi
fi

load ${devtype} ${devnum} ${kernel_addr_r} ${prefix}Image
booti ${kernel_addr_r} - ${fdt_addr_r}
