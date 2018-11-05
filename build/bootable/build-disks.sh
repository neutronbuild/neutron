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

# this file generates vmdk disks from raw blobs and a grub bios bootloader
set -e -o pipefail +h && [ -n "$DEBUG" ] && set -x
DIR=$(dirname "$(readlink -f "$0")")
. "${DIR}/log.sh"

function convert() {
  local mount=$1
  local vmdk=$2
  cd "${PACKAGE}"
  
  # get size using a cpio archive
  (
      cd "$mount"
      find . | cpio -o >"${PACKAGE}/$vmdk.img.cpio"
  )
  root_disk_size=$(stat -c %s "${PACKAGE}/$vmdk.img.cpio")
  root_disk_size=$(((root_disk_size+(1*1024))/1024*1024))
  four_mb=$((4*1024*1024))
  if [ $((root_disk_size)) -lt $((four_mb)) ];  then
    root_disk_size=$four_mb
  fi
  log3 "root size on disk is $root_disk_size"


  #################################### partition setup
  ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)


  #################################### extract root fs
  log3 "formatting linux partition"  
  dd if=/dev/zero of="$vmdk.img.root" bs=1M count=$((root_disk_size/(1024*1024)))
  mkfs.ext4 -F -L "neutronroot" "$vmdk.img.root"

  log3 "copying root fs"
  mp=$(mktemp -d)

  mount -o loop "$vmdk.img.root" "$mp"
  (
      cd "$mp"
      cpio -id < "${PACKAGE}/$vmdk.img.cpio"
  )


  #################################### partition setup
  disk_size=$(((root_disk_size+(2*1024*1024))/1024*1024))
  
  log3 "allocating raw image of ${brprpl}${disk_size}${reset}"
  dd if=/dev/zero of="$vmdk.img" bs=1M count=$((disk_size/(1024*1024)))

  log3 "creating partition table"

  sgdisk --clear \
    --new 1:2048:-0 --typecode=1:8300 --change-name=1:'Linux system' --partition-guid=1:$ROOT_UUID \
    $vmdk.img

  sgdisk -p $vmdk.img

  umount "$mp"

  ################################# burn raw image
  dd if="$vmdk.img.root" of="$vmdk.img" bs=512 conv=notrunc seek=$((2048))

  log3 "converting raw image ${brprpl}${vmdk}.img${reset} into ${brprpl}${vmdk}${reset}"
  qemu-img convert -f raw -O vmdk -o 'compat6,adapter_type=lsilogic,subformat=streamOptimized' "$vmdk.img" "$vmdk"
  rm "$vmdk".img*
}

function convert_with_efi() {
  local mount=$1
  local vmdk=$2
  cd "${PACKAGE}"
  
  # get size using a cpio archive
  (
      cd "$mount"
      find . | cpio -o >"${PACKAGE}/$vmdk.img.cpio"
  )
  root_disk_size=$(stat -c %s "${PACKAGE}/$vmdk.img.cpio")
  root_disk_size=$(((root_disk_size+(1*1024))/1024*1024))
  four_mb=$((4*1024*1024))
  if [ $((root_disk_size)) -lt $((four_mb)) ];  then
    root_disk_size=$four_mb
  fi
  log3 "root size on disk is $root_disk_size"


  #################################### partition setup
  BOOT_UUID=$(cat /proc/sys/kernel/random/uuid)
  ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)


  #################################### extract root fs
  log3 "formatting linux partition"  
  dd if=/dev/zero of="$vmdk.img.root" bs=1M count=$((root_disk_size/(1024*1024)))
  mkfs.ext4 -F -L "neutronroot" "$vmdk.img.root"

  log3 "copying root fs"
  mp=$(mktemp -d)

  mount -o loop "$vmdk.img.root" "$mp"
  (
      cd "$mp"
      cpio -id < "${PACKAGE}/$vmdk.img.cpio"
  )


  ################################### extract boot efi
  log3 "formatting boot partition"
  mkfs.vfat -C "$vmdk.img.boot" $((100*1024))

  log3 "setup grup on boot disk"
  mpboot=$(mktemp -d)
  mount -o loop "$vmdk.img.boot" "$mpboot"
  
  mkdir -p ${mpboot}/EFI/BOOT
  
  mkdir -p "${mp}/boot/grub2"
  ln -sfv grub2 "${mp}/boot/grub"

  log3 "configure grub"
  rm -rf "${mp}/boot/grub2/fonts"
  cp "${DIR}/boot/ascii.pf2" "${mp}/boot/grub2/"
  mkdir -p "${mp}/boot/grub2/themes/photon"
  cp "${DIR}"/boot/splash.png "${mp}/boot/grub2/themes/photon/photon.png"
  cp "${DIR}"/boot/terminal_*.tga "${mp}/boot/grub2/themes/photon/"
  cp "${DIR}"/boot/theme.txt "${mp}/boot/grub2/themes/photon/"
  # linux-esx tries to mount rootfs even before nvme got initialized.
  # rootwait fixes this issue
  EXTRA_PARAMS=""
  if [[ "$1" == *"nvme"* ]]; then
      EXTRA_PARAMS=rootwait
  fi

  cat > "${mp}"/boot/grub2/grub.cfg << EOF
# Begin /boot/grub2/grub.cfg

set default=0
set timeout=5
search --label neutronroot --set prefix
loadfont (\$prefix)/boot/grub2/ascii.pf2

insmod gfxterm
insmod vbe
insmod tga
insmod png
insmod ext2
insmod part_gpt

set gfxmode="640x480"
gfxpayload=keep

terminal_output gfxterm

set theme=(\$prefix)/boot/grub2/themes/photon/theme.txt
load_env -f (\$prefix)/boot/photon.cfg
if [ -f  (\$prefix)/boot/systemd.cfg ]; then
    load_env -f (\$prefix)/boot/systemd.cfg
else
    set systemd_cmdline=net.ifnames=0
fi
set rootpartition=PARTUUID=$ROOT_UUID

menuentry "Photon" {
    linux (\$prefix)/boot/\$photon_linux root=\$rootpartition \$photon_cmdline \$systemd_cmdline $EXTRA_PARAMS
    if [ -f (\$prefix)/boot/\$photon_initrd ]; then
        initrd (\$prefix)/boot/\$photon_initrd
    fi
}
# End (\$prefix)/boot/grub2/grub.cfg
EOF


  cat > "${mpboot}"/EFI/BOOT/grub.cfg <<EOF 
search --label neutronroot --set prefix
configfile (\$prefix)/boot/grub2/grub.cfg
EOF

  grub2-efi-mkimage \
        -d /usr/lib/grub/x86_64-efi \
        -o ${mpboot}/EFI/BOOT/BOOTX64.EFI \
        -p /EFI/BOOT \
        -O x86_64-efi \
        part_gpt fat ext2 iso9660 gzio linux acpi normal cpio crypto disk boot crc64 \
        search_fs_uuid tftp verify video gfxterm tga png configfile search

  umount "$mpboot"
  umount "$mp"

  
  #################################### partition setup
  boot_size=$(stat -c %s "$vmdk.img.boot")
  boot_size_kb=$(( ( ( ($boot_size+1024-1) / 1024 ) + 1024-1) / 1024 * 1024 ))
  boot_size_sectors=$(( $boot_size_kb * 2 ))

  root_size=$(stat -c %s "$vmdk.img.root")
  root_size_kb=$(( ( ( ($root_size+1024-1) / 1024 ) + 1024-1) / 1024 * 1024 ))
  root_size_sectors=$(( $root_size_kb * 2 ))

  disk_size=$(((boot_size+root_size+(4*1024*1024))/1024*1024))
  
  log3 "allocating raw image of ${brprpl}${disk_size}${reset}"
  dd if=/dev/zero of="$vmdk.img" bs=1M count=$((disk_size/(1024*1024)))

  log3 "creating partition table"

  sgdisk --clear \
    --new 1:2048:$((2048+boot_size_sectors-1)) --typecode=1:ef00 --change-name=1:'EFI System' --partition-guid=1:$BOOT_UUID --attributes 1:set:2 \
    --new 2:$((2048+boot_size_sectors)):-0 --typecode=2:8300 --change-name=2:'Linux system' --partition-guid=2:$ROOT_UUID \
    $vmdk.img

  sgdisk -p $vmdk.img 1>&2


  ################################# burn raw image
  dd if="$vmdk.img.boot" of="$vmdk.img" bs=512 conv=notrunc count=$boot_size_sectors seek=2048
  dd if="$vmdk.img.root" of="$vmdk.img" bs=512 conv=notrunc count=$root_size_sectors seek=$((2048+boot_size_sectors))

  log3 "converting raw image ${brprpl}${vmdk}.img${reset} into ${brprpl}${vmdk}${reset}"
  qemu-img convert -f raw -O vmdk -o 'compat6,adapter_type=lsilogic,subformat=streamOptimized' "$vmdk.img" "$vmdk"
  rm "$vmdk".img*
}

function convert_with_bios() {
  local mount=$1
  local vmdk=$2
  cd "${PACKAGE}"
  
  # get size using a cpio archive
  (
      cd "$mount"
      find . | cpio -o >"${PACKAGE}/$vmdk.img.cpio"
  )
  root_disk_size=$(stat -c %s "${PACKAGE}/$vmdk.img.cpio")
  root_disk_size=$(((root_disk_size+(1*1024))/1024*1024))
  four_mb=$((4*1024*1024))
  if [ $((root_disk_size)) -lt $((four_mb)) ];  then
    root_disk_size=$four_mb
  fi
  log3 "root size on disk is $root_disk_size"


  #################################### partition setup
  BOOT_UUID=$(cat /proc/sys/kernel/random/uuid)
  ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)


  #################################### extract root fs
  log3 "formatting linux partition"  
  dd if=/dev/zero of="$vmdk.img.root" bs=1M count=$((root_disk_size/(1024*1024)))
  mkfs.ext4 -F -L "neutronroot" "$vmdk.img.root"

  log3 "copying root fs"
  mp=$(mktemp -d)

  mount -o loop "$vmdk.img.root" "$mp"
  (
      cd "$mp"
      cpio -id < "${PACKAGE}/$vmdk.img.cpio"
  )


  ################################### extract boot bios
  log3 "setup grup on root disk"
  
  mkdir -p "${mp}/boot/grub2"
  ln -sfv grub2 "${mp}/boot/grub"

  log3 "configure grub"
  rm -rf "${mp}/boot/grub2/fonts"
  cp "${DIR}/boot/ascii.pf2" "${mp}/boot/grub2/"
  mkdir -p "${mp}/boot/grub2/themes/photon"
  cp "${DIR}"/boot/splash.png "${mp}/boot/grub2/themes/photon/photon.png"
  cp "${DIR}"/boot/terminal_*.tga "${mp}/boot/grub2/themes/photon/"
  cp "${DIR}"/boot/theme.txt "${mp}/boot/grub2/themes/photon/"
  # linux-esx tries to mount rootfs even before nvme got initialized.
  # rootwait fixes this issue
  EXTRA_PARAMS=""
  if [[ "$1" == *"nvme"* ]]; then
      EXTRA_PARAMS=rootwait
  fi

  cat > "${mp}/boot/grub2/grub.cfg" << EOF
# Begin /boot/grub2/grub.cfg

set default=0
set timeout=5
search --label neutronroot
loadfont /boot/grub2/ascii.pf2

insmod gfxterm
insmod vbe
insmod tga
insmod png
insmod ext2
insmod part_gpt

set gfxmode="640x480"
gfxpayload=keep

terminal_output gfxterm

set theme=/boot/grub2/themes/photon/theme.txt
load_env -f /boot/photon.cfg
if [ -f  /boot/systemd.cfg ]; then
    load_env -f /boot/systemd.cfg
else
    set systemd_cmdline=net.ifnames=0
fi
set rootpartition=PARTUUID=$ROOT_UUID

menuentry "Photon" {
    linux /boot/\$photon_linux root=\$rootpartition \$photon_cmdline \$systemd_cmdline $EXTRA_PARAMS
    if [ -f /boot/\$photon_initrd ]; then
        initrd /boot/\$photon_initrd
    fi
}
# End /boot/grub2/grub.cfg
EOF
  

  #################################### partition size setup
  boot_size=$((4*1024*1024))
  boot_size_kb=$(( ( ( ($boot_size+1024-1) / 1024 ) + 1024-1) / 1024 * 1024 ))

  root_size=$(stat -c %s "$vmdk.img.root")

  disk_size=$(((boot_size+root_size+(4*1024*1024))/1024*1024))
  
  log3 "allocating raw image of ${brprpl}${disk_size}${reset}"
  dd if=/dev/zero of="$vmdk.img" bs=1M count=$((disk_size/(1024*1024)))

  log3 "creating partition table"

  sgdisk --clear \
    --new 1:2048:$((2048+boot_size_kb-1)) --typecode=1:ef02 --change-name=1:'BIOS System' --partition-guid=1:$BOOT_UUID \
    --new 2:$((2048+boot_size_kb)):-0 --typecode=2:8300 --change-name=2:'Linux system' --partition-guid=2:$ROOT_UUID \
    $vmdk.img

  sgdisk -p $vmdk.img

  disk=$(losetup -f -P --show "$vmdk.img")
    
  grub2-install \
    --target=i386-pc \
    --modules "part_gpt gfxterm vbe tga png ext2" \
    --no-floppy \
    --force \
    --boot-directory="${mp}/boot" "$disk"

  losetup -d $disk
  umount "$mp"

  echo "root -- $((2048+boot_size_kb))"
  ################################# burn raw image
  dd if="$vmdk.img.root" of="$vmdk.img" bs=512 conv=notrunc seek=$((2048+boot_size_kb))

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
    if [ "$i" == "0" ]; then
        convert_with_bios "${PACKAGE}/${IMAGEROOTS[$i]}" "${IMAGES[$i]}.vmdk" 
    else
        convert "${PACKAGE}/${IMAGEROOTS[$i]}" "${IMAGES[$i]}.vmdk" 
    fi
  done

  log2 "VMDK Sizes"
  log2 "$(du -h ./*.vmdk)"

else
  usage
fi
