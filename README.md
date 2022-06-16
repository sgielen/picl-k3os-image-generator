# PiCl k3os image generator

This project can be used to generate images for k3os compatible with various armv8 (aarch64) devices:

- Raspberry Pi model 3B+
- Raspberry Pi model 4
- Orange Pi PC 2
- (Other devices may be compatible as well. PRs welcome! Please file an issue if you need any help with porting.)

## Getting Started

- First, make a list of devices you want to use in your k3s cluster, their hardware types and the MAC addresses of their eth0 interface. (To find the MAC, boot any supported OS, perhaps the one that comes on the included SD card if you have one, and `cat /sys/class/net/eth0/address`. Or, just continue with a dummy config and the initial boot will say "there is no config for MAC xx:xx:xx:xx:xx:xx", and then you know what to call it.)
- In the config/ directory, create one configuration file for each device, named as `{MAC}.yaml` (e.g. `dc:a6:32:aa:bb:cc.yaml`). The appropriate file will be used as a config.yaml eventually.
    - You can use environment variable references in these configuration files. During execution of `./build-image.sh` the references will be expanded via `envsubst`.
- For Raspberry Pi devices, you can choose which firmware to use for the build by setting an env variable `RASPBERRY_PI_FIRMWARE`
    - If unset, the script uses a known good version (set as `DEFAULT_GOOD_PI_VERSION` in the script)
    - Set to `latest`, which instructs the script to always pull the latest version available in the raspberry pi firmware repo (e.g. `export RASPBERRY_PI_FIRMWARE=latest`)
    - Set to a specific version, which instructs the script to use that version (e.g. `export RASPBERRY_PI_FIRMWARE="1.20200212"`)
- Run `./build-image.sh <imagetype>` where imagetype is `raspberrypi` or `orangepipc2`. It will check whether all dependencies are installed for creating the image, then proceeds to create the image as `picl-k3os-{k3osversion}-{imagetype}.img`.
  - If you have multiple images, you can also run `./build-image.sh all` to build all supported image types in one go for convenience.
- Write the image to the SD cards for each device. The SD card must be at least 1 GB.
- Insert the SD cards into the devices, minding correct image type per device type, of course. On first boot, they will resize their root filesystems to the size of the SD card and will install their own config.yaml in the correct place based on their MAC address. After this, they will reboot.
- On subsequent boots, k3os will run automatically with the correct per-device config.yaml.

## Performing updates

When you want to simply change the config.yaml of your devices, you don't need to reprovision the SD cards. Instead, you can
run `sudo mount -o remount,rw /k3os/system` on the running systems and make the changes to `/k3os/system/config.yaml`, then
reboot. Make sure to keep the config.yaml up-to-date with the respective yaml in your checkout of this repository, in case
you do need to provision a new image, though!

To autoupgrade to new k3os versions you may enable the k3os upgrade feature by adding this label to your `config.yaml`
```
k3os:
    labels:
        k3os.io/upgrade: latest

```

In case there are major changes to this repository and you want to perform a reinstall on your devices, it's
easiest to create a new image and flash it onto the device. However, depending on where your cluster data is stored, this may
mean you need to reapply cluster configs to your master or use a k8s backup and restore solution like [velero](https://velero.io/).

## Troubleshooting

If your device should be supported, but has problems coming up, attach a screen and check what happens during boot. Normally,
on initial boot, you should see the Linux kernel booting, some messages appearing regarding the resizing of the root FS, then
a reboot; on subsequent boots, you should see OpenRC starting, then the k3os logo and a prompt to login.

At all times, check whether your power supply is sufficient if you're having problems. Raspberry Pis and similar devices are
known to experience weird issues when the power supply cannot provide sufficient power or an improper (data/no charge) cable
is used. Double-check this, or try another one, even if you think the problem is unlikely to be caused by this.

If you don't see Linux kernel messages appearing at all, but the device is supported, check whether you formatted your SD card properly, or check if you can run Raspbian or Armbian on the device.

If you see Linux appearing but there is an error during resizing, something may be up with your SD card. Change the
init.resizefs to include the line "exec busybox ash" before where you expect the error occurs, and run the steps manually
until you find the culprit.

If resizing works but after reboot you cannot get start k3os, use the same trick: include the line "exec busybox ash" in
the normal init script and try to start k3os manually. You may need to load additional kernel modules.

Anytime you think the scripts or documentation could be improved, please file an issue or a PR and we'll be happy to help.

### USB 3.0 disk performance issues

In case you hit performance issues with USB 3.0 mass storage devices adding the devices to `quirks.txt` may help.
See [example](https://www.raspberrypi.org/forums/viewtopic.php?t=245931)

## Docker

You can build this project in Docker, e.g. when you'd rather not install dependencies on your host machine or when you're
building on a Mac or Windows.

If you want to build in Docker, you can build a container containing the dependencies using:

```
docker build . -t picl-builder:latest
```

Then, run the container using:

```
docker run -e TARGET=all -v ${PWD}:/app -v /dev:/dev --privileged picl-builder:latest
```

The images will be written into your local directory once the container is done.

## Authors & License

The initial code was written by Dennis Brentjes and Sjors Gielen, with many
[contributors since then](https://github.com/sgielen/picl-k3os-image-generator/graphs/contributors),
thanks to all. Further contributions welcome!

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
