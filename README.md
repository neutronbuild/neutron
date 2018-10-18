# Appliance

## A modern OVA build

## To Do

- [ ] Remove dependencies on hosted files
- [ ] Remove dependencies on hosted containers
- [ ] Remove Harbor, Admiral, UI
- [ ] Remove other appliance services
- [ ] Add reference service and documentation
- [ ] Clean up READMEs for build
- [ ] Fix copyright headers
- [ ] Clean up and document flags to OVA build
- [ ] Roadmap
- [ ] Move the below how to section to proper docs
- [ ] Document customizing DCUI

## Long term items (put in a roadmap)

- [ ] Unforked repo.
- [ ] Remove dependency on OVF keys. Perhaps package a config webapp in initrd.
- [ ] Develop a versioning and deliverable strategy. This is now a tool to build OVAs, not an OVA itself.
- [ ] Move away from privileged loopback devices in the builder.

## How to run the builder

```bash
# create the build container
make ova-builder
# run the build script with caching enabled
make ova
```
