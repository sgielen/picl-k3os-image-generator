#!/bin/bash

echo "************************************"
files=("./"*.img)
PS3='Select image file, or 0 to exit: '
select file in "${files[@]}"; do
	if [[ $REPLY == "0" ]]; then
		echo 'Bye!' >&2
		exit
	# test for zero length of string
	elif [[ -z $file ]]; then
		echo 'Invalid choice, try again' >&2
	else
		break
	fi
done

if [[ "$OSTYPE" == "darwin"* ]]; then
	echo "********* running on OSX *********"
	echo "********* available drives *********"
	diskutil list external physical
	echo "************************************"
	drives=($(diskutil list external physical | sed -n '/\/dev\//p' | awk '{print $1}'))
	PS3='Select destination drive, or 0 to exit: '
	select drive in "${drives[@]}"; do
		if [[ $REPLY == "0" ]]; then
			echo 'Bye!' >&2
			exit
		# test for zero length of string
		elif [[ -z $drive ]]; then
			echo 'Invalid choice, try again' >&2
		else
			break
		fi
	done
	echo "************************************"
	rdrive=($(echo $drive | sed 's/\/dev\/disk/\/dev\/rdisk/'))
	echo -e "  burning file: $file\n  to drive: $rdrive ($drive)"
	echo "$rdrive ($drive) WILL BE DELETED !!!"

	read -r -p "Are you sure? [y/N] " response
	if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
		# burn image
		echo you will be asked for sudo password...
		diskutil unmountDisk $drive
		# dd status=progress is unfortunately not supported
		sudo dd bs=32m if=$file of=$rdrive
		diskutil list $drive
		diskutil unmountDisk $drive
	else
		echo 'Bye!' >&2
		exit
	fi
else
	echo "********* running on non OSX -> not yet implemented *********"

fi
