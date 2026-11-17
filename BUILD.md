# macOS VM stack on this branch (`macos-vm`)

This branch wires the owner's macOS guest VM stack ([omvm](https://github.com/sapoepsilon/omvm)) into the Apple Silicon install. The packages, their recipes and the full build, hosting and test steps live in [sapoepsilon/omarchy-mac-pkgs `macos-vm`, BUILD.md](https://github.com/sapoepsilon/omarchy-mac-pkgs/blob/macos-vm/BUILD.md).

## What this branch adds

- `install/hardware/apple/macos-vm.sh`, run from `install/hardware/all.sh`: on an Apple Silicon Mac whose install asked for macOS VMs (`/etc/omarchy/macos-vm.enabled`, or `OMARCHY_MACOS_VM=1` for a script install, which writes it), installs the `omarchy-macos-vm` hook package (from `/var/lib/omarchy/macos-vm/repo/`, `/boot/efi/omarchy/macos-vm/repo/`, or a configured repository) and enables `omarchy-macos-vm-setup.service`. That service installs the rest at the next boot. Without the request the leaf does nothing.
- `test/shell.d/apple-macos-vm-test.sh`.

## How an image gets it

Images are not built from this repository's install scripts: omacom/omarchy-mac-installer's `image-builder/` installs a signed candidate set (or the edge channel), with `omarchy-mac-boot` and `omarchy-mac` from a platform repository commit (`platform_sources`). For an image with the stack, item (d) must:

1. Take `omarchy-mac-boot` from sapoepsilon/omarchy-mac-pkgs `macos-vm` (first boot turns install.conf's `macos_vm=1` into `/etc/omarchy/macos-vm.enabled`; the boot check accepts the side kernel).
2. Install `omarchy-macos-vm` into `@` before the `@factory` seal and apply `80-omarchy-macos-vm.preset`.
3. Carry `linux-aurora-vmapple`, `qemu-vmapple`, `mesa-honeykrisp-vmapple` and `omvm` in `/var/lib/omarchy/macos-vm/repo/` (or on the ESP in `omarchy/macos-vm/repo/`).
4. Keep that image private: the kernel carries an unlicensed patch, and the public inspection refuses unsigned packages.

## Build and test

On the laptop (Omarchy, aarch64), follow omarchy-mac-pkgs `macos-vm` BUILD.md for the packages. For this branch's leaf:

```bash
bash test/shell.d/apple-macos-vm-test.sh
# On a script install with the hook package in /var/lib/omarchy/macos-vm/repo/:
OMARCHY_MACOS_VM=1 ./install.sh
```
