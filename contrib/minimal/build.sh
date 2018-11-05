#!/bin/bash

echo "building minimal ova"

TAG=$(git describe --abbrev=0 --tags || true) # e.g. `v0.9.0`
REV=$(git rev-parse --short=8 HEAD)
BUILD_OVA_REVISION="${TAG}-${BUILD_NUMBER}-${REV}"

docker run -it --rm \
  --privileged \
  -v $(pwd):/build/out/ \
  -e BUILD_OVA_REVISION=${BUILD_OVA_REVISION} \
  -e TERM \
  docker.io/neutronbuild/neutron:latest
