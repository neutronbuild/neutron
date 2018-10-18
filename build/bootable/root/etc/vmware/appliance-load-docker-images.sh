#!/usr/bin/bash
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
set -euf -o pipefail
source /installer.env

if [[ ! -f /etc/vmware/firstboot ]]; then
  # Only load the docker images if it's the first time booting
  ls "/etc/cache/docker/" | while read line; do
    docker load -i "/etc/cache/docker/$line"
  done;
  date -u +"%Y-%m-%dT%H:%M:%SZ" > /etc/vmware/firstboot
else
  echo "No images to load...."
fi
