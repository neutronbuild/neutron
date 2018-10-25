#!/bin/bash
# TODO copyright
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

# fail on error, unassigned vars or failed pipes
set -e -o pipefail +h && [ -n "$DEBUG" ] && set -x
DIR=$(dirname "$(readlink -f "$0")")
. "${DIR}/log.sh"

# TODO(morris-jason) merge with https://github.com/vmware/photon/blob/2.0-Update104/common/data/packages_full.json
# TODO(morris-jason) use normal kernel
packages=(
  filesystem
  bash
  shadow
  coreutils
  findutils
  systemd
  util-linux
  pkgconfig
  dbus
  cpio
  photon-release
  tdnf
  openssh
  linux-esx
  sed
  gzip
  zip
  tar
  xz
  bzip2
  glibc
  iana-etc
  ca-certificates
  curl
  which
  initramfs
  krb5
  motd
  procps-ng
  bc
  kmod
  libdb
  glibc-lang
  vim
  haveged
  ethtool
  gawk
  socat
  git
  nfs-utils
  cifs-utils
  ebtables
  iproute2
  iptables
  iputils
  cdrkit
  xfsprogs
  sudo
  lvm2
  parted
  gptfdisk
  e2fsprogs
  docker-17.12.1-1.ph1
  gzip
  net-tools
  logrotate
  sshpass
  open-vm-tools
  openjre
  python-pip
)

function set_base() {
  src="${1}"
  rt="${2}"

  log2 "preparing install stage"
  log3 "configuring ${brprpl}tdnf${reset}"
  install -D --mode=0644 --owner=root --group=root /etc/pki/rpm-gpg/VMWARE-RPM-GPG-KEY "${rt}/etc/pki/rpm-gpg/VMWARE-RPM-GPG-KEY"
  mkdir -p "${rt}/var/lib/rpm"
  mkdir -p "${rt}/cache/tdnf"
  log3 "initializing ${brprpl}rpm db${reset}"
  rpm --root "${rt}/" --initdb
  rpm --root "${rt}/" --import "${rt}/etc/pki/rpm-gpg/VMWARE-RPM-GPG-KEY"

  log3 "configuring ${brprpl}yum repos${reset}"
  mkdir -p "${rt}/etc/yum.repos.d/"
  rm /etc/yum.repos.d/{photon,photon-updates}.repo
  cp "${DIR}"/repo/*-remote.repo /etc/yum.repos.d/
  cp -a /etc/yum.repos.d/ "${rt}/etc/"

  log3 "configuring temporary ${brprpl}resolv.conf${reset}"
  cp /etc/resolv.conf "${rt}/etc/"

  log3 "verifying yum and tdnf setup"
  tdnf repolist --refresh

  log3 "installing ${brprpl}tdnf packages${reset}"
  tdnf install --installroot "${rt}/" --refresh -y \
    $(printf " %s" "${packages[@]}")


  log3 "installing pyyaml"
  pip install pyyaml

  log3 "installing - docker compose"
  # TODO(morris-jason) find some way to configure these versions
  curl -o /usr/local/bin/docker-compose -L'#' "https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m)" 
  chmod +x /usr/local/bin/docker-compose

  log3 "installing - jq"
  curl -o /usr/bin/jq -L'#' "https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64"
  chmod +x /usr/bin/jq

  log3 "installing ${brprpl}root${reset}"
  cp -a "${src}/root/." "${rt}/"
}

function usage() {
  echo "Usage: $0 -r root-location 1>&2"
  exit 1
}

while getopts "r:" flag
do
    case $flag in

        r)
            # Required. Package name
            ROOT="$OPTARG"
            ;;

        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))
if [[ -n "$*" || -z "${ROOT}" ]]; then
    usage
fi

log2 "install OS to ${ROOT}"

set_base "${DIR}" "${ROOT}"