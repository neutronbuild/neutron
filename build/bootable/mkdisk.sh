mkdir -p /build/out
touch /build/out/ova-manifest.yml
/build/bootable/build-main.sh -m /build/out/ova-manifest.yml -r /build/out/

export disk_size=1gb
export img=disk.raw
export part_num=1
export ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)
export BOOT_UUID=$(cat /proc/sys/kernel/random/uuid)

######################################
################### PREP FILESYSTEM
######################################

BOOT_DIRECTORY=/boot/

rm -rf "${root}/boot/grub2/fonts"
cp "${DIR}/boot/ascii.pf2" "${root}/boot/grub2/"
mkdir -p "${root}/boot/grub2/themes/photon"
cp "${DIR}"/boot/splash.png "${root}/boot/grub2/themes/photon/photon.png"
cp "${DIR}"/boot/terminal_*.tga "${root}/boot/grub2/themes/photon/"
cp "${DIR}"/boot//theme.txt "${root}/boot/grub2/themes/photon/"

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
set rootpartition=PARTUUID=$ROOT_UUID
menuentry "Photon" {
    linux ${BOOT_DIRECTORY}\$photon_linux root=\$rootpartition \$photon_cmdline \$systemd_cmdline $EXTRA_PARAMS
    if [ -f ${BOOT_DIRECTORY}\$photon_initrd ]; then
        initrd ${BOOT_DIRECTORY}\$photon_initrd
    fi
}
# End /boot/grub2/grub.cfg
EOF

######################################
################### CREATE IMAGE FILESYSTEM
######################################

fallocate -l "$disk_size" -o 1024 "$img"
sgdisk -Z -og "$img"
sgdisk -n $part_num:2048:+2M -c $part_num:"BIOS Boot" -t $part_num:ef02 -u $part_num:$BOOT_UUID "$img"
export part_num=$((part_num+1))
sgdisk -N $part_num -c $part_num:"Linux system" -t $part_num:8300 -u $part_num:$ROOT_UUID "$img"

grub2-mkimage --format=i386-pc -o boot.img -p / part_gpt gfxterm vbe tga png ext2

dd if=boot.img of=$img bs=1024 count=2M conv=notrunc seek=2048

fallocate -l 1gb -o 1024 root.img

mkfs.ext4 -F root.img

mkisofs -o root.iso "${root}"

dd if=root.iso of=$img bs=1024 conv=notrunc seek=6144

qemu-img convert -f raw -O vmdk -o 'compat6,adapter_type=lsilogic,subformat=streamOptimized' "$img" "$vmdk"

wget https://github.com/vmware/photon-docker-image/blob/2.0-20181017/docker/photon-rootfs-2.0-045c453.tar.bz2?raw=true -O photonfs.tar.bz2
