# Appliance

## A modern OVA build

### Problem 

VMWare Studio is the existing product for authoring Virtual Machines Appliances (or OVAs) for use on vSphere, VMware Fusion, and other VMware infrastructure.

Unofruntately, there is no notable development occurring on the product - with no support for vSphere 6.7 and no present release timeline. 

The last official release was in 2012. 

### Progress

The lack of a modern Virtual Machine Appliance Builder has led some VMware products to devise their own solutions, for example:

- vSphere Integrated Containers utilized a [collection of bash scripts](https://github.com/vmware/vic-product) to build an appliance on a local machine.
- Utilize [HashiCorp's Packer](https://github.com/hashicorp/packer) software to build OVAs on a remote ESX through iso import/export.
- A manual process for extracting a VM as an OVA from vSphere using ovftool.

### Solution

This neutron open source project will allow a VMware developer to build a custom Virtual Machine Appliance. 

Unlike other tools, this project is composable, customizable, and built for VMware infrastructure.

- Neutron is fast, with initial build times around ~10-15 minutes.
- It is extensible, with a scripting mechanism similar to Packer.
- Powered by [Photon OS 2](https://github.com/vmware/photon/wiki/What-is-New-in-Photon-OS-2.0), a secure and minimal linux distrobution menat to run on ESX.

The result of this project is an easy to use binary that any team in VMware can use to build a Virtual Machine Appliance.


### Disclaimer

This project was originally forked from [VMware vSphere Integrated Containers (VIC)](https://github.com/vmware/vic-product). The initial goal for Neutron is to create a general purpose OVA builder, whereas the builder in VIC is specific and non-extensible. 

## To Do

- [*] Remove dependencies on hosted files
- [*] Remove dependencies on hosted containers
- [*] Remove Harbor, Admiral, UI
- [*] Remove other appliance services
- [ ] Add reference service and documentation
- [ ] Clean up READMEs for build
- [ ] Fix copyright headers
- [ ] Clean up and document flags to OVA build
- [ ] Roadmap
- [ ] Move the below how to section to proper docs
- [ ] Document customizing DCUI

- [ ] update dcui
- [ ] privileged runner
- [ ] customized kernel
- [ ] provisioners to build-app.sh
- [ ] versioned photon packages
- [ ] photon2
- [ ] Pull containers for docker-image-load with login credentials
- [ ] Build go tools (ovfenv, etc) in the build container

- [*] Unforked repo.
- [ ] ~Remove dependency on OVF keys. Perhaps package a config webapp in initrd.~
- [ ] Develop a versioning and deliverable strategy. This is now a tool to build OVAs, not an OVA itself.
- [ ] Move away from privileged loopback devices in the builder.

## How to run the builder

```bash
# create the build container. temporary step.
make ova-builder
# run the build script with caching enabled
make ova
```
