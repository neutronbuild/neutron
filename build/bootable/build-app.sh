#!/bin/bash
#TODO COPYRIGHT
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

# this build file is responsible for parsing cli args and spinning up a build container
set -e -o pipefail +h && [ -n "$DEBUG" ] && set -x
DIR=$(dirname "$(readlink -f "$0")")
. "${DIR}/log.sh"

# Importing the pubkey
log2 "configuring os"
log3 "importing local gpg key"
rpm --import /etc/pki/rpm-gpg/VMWARE-RPM-GPG-KEY

log3 "setting umask to 022"
sed -i 's/umask 027/umask 022/' /etc/profile

log3 "setting root password"
echo 'root:Vmw@re!23' | chpasswd

log3 "configuring password expiration"
chage -I -1 -m 0 -M 99999 -E -1 root

log3 "configuring ${brprpl}UTC${reset} timezone"
ln --force --symbolic /usr/share/zoneinfo/UTC /etc/localtime

log3 "configuring ${brprpl}en_US.UTF-8${reset} locale"
/usr/bin/touch /etc/locale.conf
/bin/echo "LANG=en_US.UTF-8" > /etc/locale.conf
/sbin/locale-gen.sh

log3 "configuring ${brprpl}haveged${reset}"
systemctl enable haveged

log3 "configuring ${brprpl}sshd${reset}"
echo "UseDNS no" >> /etc/ssh/sshd_config
systemctl enable sshd

log2 "running provisioners"
find script-provisioners -type f | sort -n | while read -r SCRIPT; do
  log3 "running ${brprpl}$SCRIPT${reset}"
  ./"$SCRIPT"
done;

log2 "setting up systemd"
# Enable systemd services
systemctl enable appliance-mounts.target repartition.service resizefs.service
systemctl enable appliance-environment.service
systemctl enable appliance-ready.target
systemctl enable appliance-load-docker-images.service
systemctl enable appliance-tls.service
systemctl enable sshd_permitrootlogin.service
systemctl enable getty@tty2.service
systemctl enable appliance-network.service appliance-firewall.service

# Set our appliance target as the default boot target
systemctl set-default appliance.target

log3 "hardening ssh"
# Warning message for client ssh
message="##########################################################################
Authorized personnel only.
##########################################################################"

# Modify ssh config to display warning message before log on
echo "$message" > "/etc/issue.net"
banner=$(grep "Banner" /etc/ssh/sshd_config)
if [ -z "$banner" ]; then
    echo "Banner /etc/issue.net" >> "/etc/ssh/sshd_config"
else
    sed -i "s/.*Banner.*/Banner\ \/etc\/issue\.net/g" /etc/ssh/sshd_config
fi

# Overwirte /etc/motd to display warning message after log on
echo "$message" > "/etc/motd"

# Disable IPv6 redirection and router advertisements in kernel settings
settings="net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0"
echo "$settings" > "/etc/sysctl.d/40-ipv6.conf"

# Clear SSH host keys
rm -f /etc/ssh/{ssh_host_dsa_key,ssh_host_dsa_key.pub,ssh_host_ecdsa_key,ssh_host_ecdsa_key.pub,ssh_host_ed25519_key,ssh_host_ed25519_key.pub,ssh_host_rsa_key,ssh_host_rsa_key.pub}

# Hardening SSH configuration
afsetting=$(grep "AllowAgentForwarding" /etc/ssh/sshd_config)
if [ -z "$afsetting" ]; then
    echo "AllowAgentForwarding no" >> "/etc/ssh/sshd_config"
else
    sed -i "s/.*AllowAgentForwarding.*/AllowAgentForwarding\ no/g" /etc/ssh/sshd_config
fi

tcpfsetting=$(grep "AllowTcpForwarding" /etc/ssh/sshd_config)
if [ -z "$tcpfsetting" ]; then
    echo "AllowTcpForwarding no" >> "/etc/ssh/sshd_config"
else
    sed -i "s/.*AllowTcpForwarding.*/AllowTcpForwarding\ no/g" /etc/ssh/sshd_config
fi

log2 "cleaning up base os disk"
tdnf clean all
rm -rf /tmp/* /var/tmp/*

/sbin/ldconfig
/usr/sbin/pwconv
/usr/sbin/grpconv
/bin/systemd-machine-id-setup

rm /etc/resolv.conf
ln -sf ../run/systemd/resolve/resolv.conf /etc/resolv.conf

log3 "removing caches"
find /var/cache -type f -exec rm -rf {} \;

log3 "removing bash history"
# Remove Bash history
unset HISTFILE
echo -n > /root/.bash_history

# Clean up log files
log3 "cleaning log files"
find /var/log -type f | while read -r f; do echo -ne '' > "$f"; done;

log3 "clearing last login information"
echo -ne '' >/var/log/lastlog
echo -ne '' >/var/log/wtmp
echo -ne '' >/var/log/btmp

log3 "resetting bashrs"
echo -ne '' > /root/.bashrc
echo -ne '' > /root/.bash_profile
echo 'shopt -s histappend' >> /root/.bash_profile
echo 'export PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"' >> /root/.bash_profile

# Zero out the free space to save space in the final image
log3 "zero out free space"
dd if=/dev/zero of=/EMPTY bs=1M  2>/dev/null || echo "dd exit code $? is suppressed"
rm -f /EMPTY

log3 "syncing fs"
sync

# seal the template
> /etc/machine-id
