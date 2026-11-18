# macOS VM stack on this branch (`macos-vm`)

This branch wires the owner's macOS guest VM stack ([omvm](https://github.com/sapoepsilon/omvm)) into the Apple Silicon install. The packages, their recipes and the full build, hosting and test steps live in [sapoepsilon/omarchy-mac-pkgs `macos-vm`, BUILD.md](https://github.com/sapoepsilon/omarchy-mac-pkgs/blob/macos-vm/BUILD.md).

## What this branch adds

- `install/hardware/apple/macos-vm.sh`, run from `install/hardware/all.sh`: on an Apple Silicon Mac whose install asked for macOS VMs (`/etc/omarchy/macos-vm.enabled`, or `OMARCHY_MACOS_VM=1` for a script install, which writes it), installs the `omarchy-macos-vm` hook package (from `/var/lib/omarchy/macos-vm/repo/`, `/boot/efi/omarchy/macos-vm/repo/`, or a configured repository) and enables `omarchy-macos-vm-setup.service`. That service installs the rest at the next boot. Without the request the leaf does nothing.
- `bin/omarchy-macos-vm install|launch|stop|status|remove|create`, the counterpart of `omarchy-windows-vm` (which refuses Apple Silicon), and the menu rows beside Windows: **Install > macOS** (shown only on Apple Silicon, dimmed once set up; M1/M2 only, the command refuses later Macs) and **Remove > macOS**. `install` is the Windows wizard's shape: RAM (`gum choose`), cores (`gum input`), the macOS account and password, a summary and `gum confirm`; RAM and cores go to `~/.config/omarchy/macos-vm.conf` (exported as `RAM_GIB`/`CPUS` to `omvm virt`), the account to omvm's `gui.env`. It then writes the request, installs the hook, runs its setup service with the log on screen and, when the restored VM is already on VMXFER, runs `create` (`omvm ingest`, `omvm setup [--xcode]` on the side kernel, `omvm virt macos`); otherwise it prints the one-time macOS step and the next login runs `create` (omarchy-macos-vm-create.service). The disk is not a choice: it is the 160 GB sparse disk of the macOS restore. `launch [-k]` notifies, starts the VM, waits for SSH, opens it with `omvm show` fullscreen and stops it when its window closes unless `--keep-alive`. `remove` confirms (default No), takes the VM out of libvirt (`omvm virt rm`), removes the four stack packages and the request, and keeps guest images unless asked (`--purge` or a second confirm).
- `test/shell.d/apple-macos-vm-test.sh`, and `menu-test.sh` taught the new rows.

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
