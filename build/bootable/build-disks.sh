#!/bin/bash
# Copyright 2017 VMware, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# this file generates vmdk disks from raw blobs and a grub uefi bootloader
set -e -o pipefail +h && [ -n "$DEBUG" ] && set -x
DIR=$(dirname "$(readlink -f "$0")")
. "${DIR}/log.sh"

function setup_grub() {
  local root=$1
  local BOOT_UUID=$2
  local PART_UUID=$3

  log3 "install grub to ${brprpl}${root}/boot${reset}" 
  mkdir -p "${root}/boot/grub2"
  ln -sfv grub2 "${root}/boot/grub"

  BOOT_DIRECTORY=/boot/

  log3 "configure grub"
  rm -rf "${root}/boot/grub2/fonts"
  cp "${DIR}/boot/ascii.pf2" "${root}/boot/grub2/"
  mkdir -p "${root}/boot/grub2/themes/photon"
  cp "${DIR}"/boot/splash.png "${root}/boot/grub2/themes/photon/photon.png"
  cp "${DIR}"/boot/terminal_*.tga "${root}/boot/grub2/themes/photon/"
  cp "${DIR}"/boot//theme.txt "${root}/boot/grub2/themes/photon/"
  # linux-esx tries to mount rootfs even before nvme got initialized.
  # rootwait fixes this issue
  EXTRA_PARAMS=""
  if [[ "$1" == *"nvme"* ]]; then
      EXTRA_PARAMS=rootwait
  fi

  cat > "${root}/boot/grub2/grub.cfg" << EOF
# Begin /boot/grub2/grub.cfg

set default=0
set timeout=5
search -n -u $BOOT_UUID -s
loadfont ${BOOT_DIRECTORY}grub2/ascii.pf2

insmod gfxterm
insmod vbe
insmod tga
insmod png
insmod ext2
insmod part_gpt

set gfxmode="640x480"
gfxpayload=keep

terminal_output gfxterm

set theme=${BOOT_DIRECTORY}grub2/themes/photon/theme.txt
load_env -f ${BOOT_DIRECTORY}photon.cfg
if [ -f  ${BOOT_DIRECTORY}systemd.cfg ]; then
    load_env -f ${BOOT_DIRECTORY}systemd.cfg
else
    set systemd_cmdline=net.ifnames=0
fi
set rootpartition=PARTUUID=$PART_UUID

menuentry "Photon" {
    linux ${BOOT_DIRECTORY}\$photon_linux root=\$rootpartition \$photon_cmdline \$systemd_cmdline $EXTRA_PARAMS
    if [ -f ${BOOT_DIRECTORY}\$photon_initrd ]; then
        initrd ${BOOT_DIRECTORY}\$photon_initrd
    fi
}
# End /boot/grub2/grub.cfg
EOF
}

function convert() {
  local mount=$1
  local vmdk=$2
  local boot="${3:-}"
  local mp=$(mktemp -d)
  cd "${PACKAGE}"
  
  # get size using a cpio archive
  (
      cd "$mount"
      find . | cpio -o >"${PACKAGE}/$vmdk.img.cpio"
  )
  root_disk_size=$(stat -c %s "${PACKAGE}/$vmdk.img.cpio")
  root_disk_size=$(((root_disk_size+1024)/1024*1024))
  four_kilo=$((4*1024*1024))
  if [ $((root_disk_size)) -lt $((four_kilo)) ];  then
    root_disk_size=$four_kilo
  fi
  log3 "root size on disk is $root_disk_size"
  disk_size=$(((root_disk_size+(1*1024*1024*1024))/1024*1024)) # add 1GB buffer and round for boot

  log3 "allocating raw image of ${brprpl}${disk_size}${reset}"
  fallocate -l "$disk_size" -o 1024 "$vmdk.img"
  
  # partition disk
  log3 "wiping existing filesystems"
  sgdisk -Z -og "$vmdk.img"

  #################################### partition setup
  part_num=1
  UUID=$(cat /proc/sys/kernel/random/uuid)
  if [[ -n $boot ]]; then
    export BOOT_UUID=UUID
    
    log3 "creating bios boot partition"
    sgdisk -n $part_num:2048:+2M -c $part_num:"BIOS Boot" -t $part_num:ef02 -u $part_num:$UUID "$vmdk.img"

    part_num=$((part_num+1))
    UUID=$(cat /proc/sys/kernel/random/uuid)
  fi

  log3 "creating linux partition"
  sgdisk -N $part_num -c $part_num:"Linux system" -t $part_num:8300 -u $part_num:$UUID "$vmdk.img"

  #################################### extract root fs
  fallocate -l "$root_disk_size" -o 1024 "$vmdk.img.root"
  log3 "formatting linux partition"
  mkfs.ext4 -F "$vmdk.img.root"

  log3 "copying root fs"
  mount -o loop "$vmdk.img.root" "$mp"
  (
      cd "$mp"
      cpio -id < "${PACKAGE}/$vmdk.img.cpio"
  )

  ################################### extract boot efi
  if [[ -n $boot ]]; then
    log3 "setup grup on boot disk"
    setup_grub "$mp" "$BOOT_UUID" "$UUID"
    grub2-mkimage -O i386-pc -o "$vmdk.img.boot" -p "${mp}/boot" -c ${mp}/boot/grub2/grub.cfg part_gpt gfxterm vbe tga png ext2
  fi
  umount "$mp"

  ################################# burn raw image
  if [[ -n "$boot" ]]; then
    dd if="$vmdk.img.boot" of="$vmdk.img" bs=512 count=2M conv=notrunc seek=2048
    dd if="$vmdk.img.root" of="$vmdk.img" bs=512 conv=notrunc seek=6144 #2048+2M=6144
  else
    dd if="$vmdk.img.root" of="$vmdk.img" bs=512 conv=notrunc
  fi

  log3 "converting raw image ${brprpl}${vmdk}.img${reset} into ${brprpl}${vmdk}${reset}"
  qemu-img convert -f raw -O vmdk -o 'compat6,adapter_type=lsilogic,subformat=streamOptimized' "$vmdk.img" "$vmdk"
  rm "$vmdk".img*
}

function usage() {
  echo "Usage: $0 -p package-location -a [create|export] -i NAME -s SIZE -r ROOT [-i NAME -s SIZE -r ROOT]..."
  echo "  -p package-location   the working directory to use"
  echo "  -a action             the action to perform (create or export)"
  echo "  -i name               the name of an image"
  echo "  -s size               the size of an image"
  echo "  -r root               the mount point for the root of an image, relative to the package-location"
  echo "Example: $0 -p /tmp -a create -i appliance-disk1.vmdk -s 6GiB -r mnt/root -i appliance-disk2.vmdk -s 2GiB -r mnt/data"
  echo "Example: $0 -p /tmp -a create -i appliance-disk1.vmdk -i appliance-disk2.vmdk -s 6GiB -s 2GiB -r mnt/root -r mnt/data"
  exit 1
}

while getopts "p:a:i:s:r:" flag
do
    case $flag in

        p)
            # Required. Package name
            PACKAGE="$OPTARG"
            ;;

        a)
            # Required. Action: create or export
            ACTION="$OPTARG"
            ;;

        i)
            # Required, multi. Ordered list of image names
            IMAGES+=("$OPTARG")
            ;;

        r)
            # Required, multi. Ordered list of image roots
            IMAGEROOTS+=("$OPTARG")
            ;;

        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

# check there were no extra args, the required ones are set, and an equal number of each disk argument were supplied
if [[ -n "$*" || -z "${PACKAGE}" || -z "${ACTION}" || ${#IMAGES[@]} -eq 0 || ${#IMAGES[@]} -ne ${#IMAGEROOTS[@]} ]]; then
    usage
fi

if [ "${ACTION}" == "create" ]; then
  log1 "create disk images"
  for i in "${!IMAGES[@]}"; do
    log2 "creating ${IMAGES[$i]}"
    mkdir -p "${PACKAGE}/${IMAGEROOTS[$i]}"
  done

elif [ "${ACTION}" == "export" ]; then
  log1 "export images to VMDKs"
  for i in "${!IMAGES[@]}"; do
    log2 "exporting ${IMAGES[$i]} to ${IMAGES[$i]}.vmdk"
    BOOT=""
    [ "$i" == "0" ] && BOOT="1"
    convert "${PACKAGE}/${IMAGEROOTS[$i]}" "${IMAGES[$i]}.vmdk" $BOOT
  done

  log2 "VMDK Sizes"
  log2 "$(du -h ./*.vmdk)"

else
  usage
fi
