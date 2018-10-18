# Neutron OVA Build

The build process uses a collection of bash scripts to launch a docker container on your local machine
where we provision a linux OS, install VIC dependencies, and extract the filesystem to make the OVA.

## Usage

The build process is controlled from a central script, `build.sh`. This script
launches the build docker container and controls our provisioning and ova
extraction through `make`.

### Prerequisites

The build machine must have `docker`.

- `docker for Mac`: https://www.docker.com/docker-mac
- `docker for Windows`: https://www.docker.com/docker-windows

### Build bundle and OVA

#### Build script

This is the recommended way to build the OVA.

###### Versioning Components

The build script pulls the desired versions of each included component into the build container.
It accepts files in the `build` directory, URLs, or revisions and automatically sets
required environment variables.

*You must specify build step `ova-dev` when calling build.sh*

If called without any values, `build.sh` will get the latest build for each component
```
sudo ./build/build.sh ova-dev
```

###### Build Script Flow

The Neutron Builder is made up of three bash scripts `build/build.sh`, `build/build-ova.sh`, and `build/build-cache.sh`. These three scripts set up the necessary environment variables needed to build VIC, download and make the component dependencies, and kick off the bootable build in a docker container. 

The `bootable` folder contains all the files needed to make a bootable ova. These include `build-main.sh`, which organizes the calls for `build-disks.sh`, `build-base.sh`, and `build-app.sh`. 

These three scripts are self-explanatory:
 - `build-disks.sh`: Provisions local disk space for the boot and data drives. Installs grub2 to the boot drive.
 - `build-base.sh`: Installs all repo components, like a linux kernel and coreutils, to the base disks. Can be cached as a gzipped tar.
 - `build-app.sh`: Performs any necessary configuration of the ova by running all script provisioners in a chroot.

The `bootable` folder also contains ovf template and tdnf repos for building the ova.

There are many useful arguments for `build-main.sh`, but most notable is the `-b` argument for caching the base layer for faster builds. This option can be passed throught the first `build.sh` script, like `./build/build.sh ova-dev -b bin/.vic-appliance-base.tar.gz`.

The general order of execution is `build.sh` -> `build-ova.sh`  -> `build-cache.sh` -> `bootable/build-main.sh` -> `bootable/build-disks.sh` -> `bootable/build-base.sh` -> `bootable/build-app.sh` -> ova export.

## Vendor

To build the installer dependencies, ensure `GOPATH` is set, then issue the following.
``
$ make vendor
``

This will install the [dep](https://github.com/golang/dep) utility and retrieve the build dependencies via `dep ensure`.

NOTE: Dep is slow the first time you run it - it may take 10+ minutes to download all of the dependencies. This is because
dep automatically falttens the vendor folders of all dependencies. In most cases, you shouldn't need to run `make vendor`,
as our vendor directory is checked in to git.

