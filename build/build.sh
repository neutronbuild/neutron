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

# this file is responsible for parsing cli args and spinning up a build container
# wraps bootable/build-main.sh in a docker container
DEBUG=${DEBUG:-}
set -e -o pipefail +h && [ -n "$DEBUG" ] && set -x
ROOT_DIR="$GOPATH/src/github.com/neutronbuild/neutron/"
ROOT_WORK_DIR="/go/src/github.com/neutronbuild/neutron/"

TAG=$(git describe --abbrev=0 --tags) # e.g. `v0.9.0`
REV=$(git rev-parse --short=8 HEAD)
BUILD_OVA_REVISION="${TAG}-${DRONE_BUILD_NUMBER}-${REV}"
BUILD_NUMBER=${DRONE_BUILD_NUMBER:-}

function usage() {
    echo -e "Usage:
      [passthrough args for ./bootable/build-main.sh: [ -c <enable-cache> ]]
    " >&2
    exit 1
}

echo "--------------------------------------------------"
if [[ "$1" == *"help"* ]]; then
  usage
else
  echo "starting docker dev build container..."
  docker run -it --rm --privileged -v /dev:/dev\
    -v ${ROOT_DIR}/:/${ROOT_WORK_DIR}/:ro \
    -v ${ROOT_DIR}/bin/:/${ROOT_WORK_DIR}/bin/ \
    -e DEBUG=${DEBUG} \
    -e BUILD_OVA_REVISION=${BUILD_OVA_REVISION} \
    -e TAG=${TAG} \
    -e BUILD_NUMBER=${BUILD_NUMBER} \
    -e TERM -w ${ROOT_WORK_DIR} \
    docker.io/neutronbuild/neutron:latest ./build/bootable/build-main.sh -m "${ROOT_WORK_DIR}/build/ova-manifest.json" -r "${ROOT_WORK_DIR}/bin" "$@"  
fi
