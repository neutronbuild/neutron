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

set -e -o pipefail +h && [ -n "$DEBUG" ] && set -x
DIR=$(dirname $(readlink -f "$0"))
. "${DIR}/log.sh"

# TODO: GET FROM MANIFEST
images=()
downloads=()

function add() {
  src=$1
  dest=$2
  if [[ "$src" =~ ^http://|^https:// ]]; then
    curl -fL"#" "$src" -o "$dest"
  else
    cp "$src" "$dest"
    log3 "copied from local fs"
  fi
}

function cacheImages() {
  log3 "caching container images"
  mkdir -p ${CACHE}/docker/
  for img in "${images[@]}"; do
    log3 "checking cache for${img} archive"
    archive="${CACHE}/docker/$(echo "${img##*/}" | tr ':' '-').tar.gz"
    log3 "pulling${img}"
    pull=$(docker pull "$img")
    if [[ -f "$archive" && "$pull" == *"Image is up to date"* ]]; then
      log3 "cache is up to date - not saving${img}"
    else
      log3 "saving${archive##*/}"
      docker save "$img" | gzip > "$archive"
    fi
    log3 "${img} details \n$(docker images --digests -f "dangling=false" --format "tag: {{.Tag}}, digest: {{.Digest}}, age: {{.CreatedSince}}" $(echo ${img} | cut -d ':' -f1))\n"
  done

  log3 "saved all images"
}

function cacheOther() {
  log3 "caching other dependencies"
  for download in "${downloads[@]}"; do
    filename=$(basename "${download}")
    log3 "checking cache for${filename} archive"
    archive="${CACHE}/${filename}"
    if [ -f "$archive" ]; then
      log3 "cache is up to date - not saving${filename}"
    else
      log3 "downloading and saving${filename}"
      set +e
      basefile=$(ls "$(dirname "$archive")/$(echo "${filename}" | cut -f1 -d"-" | cut -f1 -d"_" | cut -f1 -d".")"* 2>/dev/null)
      [ $? -eq 0 ] && [ -f "$basefile" ] && rm "$basefile"*
      set -e
      add "${download}" "$archive"
    fi
    echo ""
  done
  log3 "saved all downloads"
}

function usage() {
  log3 "Usage: $0 -c cache-directory" 1>&2
  exit 1
}

while getopts "c:" flag
do
    case $flag in

        c)
            # Optional. Offline cache of yum packages
            CACHE="$OPTARG"
            ;;

        *)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# check there were no extra args and the required ones are set
if [ -n "$*" -o -z "${CACHE}" ]; then
    usage
fi

[ -n "${images:-}" ] && cacheImages
[ -n "${downloads:-}" ] && cacheOther
exit 0