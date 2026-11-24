# macOS guest VMs (omvm) on an Apple Silicon install that asked for them.
#
# The request is /etc/omarchy/macos-vm.enabled. On an image the installer's
# macos_vm=1 in install.conf becomes that file at first boot
# (omarchy-mac-boot); a script install sets OMARCHY_MACOS_VM=1 to write it.
# This leaf only installs the small omarchy-macos-vm hook and enables its
# service, which installs the side kernel, QEMU and the rest at the next boot
# and never changes the default boot entry. Without the request it does nothing.

omarchy-hw-aarch64-apple || return 0

# shellcheck source=../../helpers/as-root.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../helpers/as-root.sh"

macos_vm_marker="${OMARCHY_MACOS_VM_MARKER:-/etc/omarchy/macos-vm.enabled}"

if [[ ${OMARCHY_MACOS_VM:-0} == "1" && ! -e $macos_vm_marker ]]; then
  as_root install -d -m 0755 "$(dirname "$macos_vm_marker")" &&
    printf '{"version":1,"requested_by":"install.sh"}\n' | as_root tee "$macos_vm_marker" >/dev/null
fi
[[ -e $macos_vm_marker ]] || return 0

if omarchy-pkg-missing omarchy-macos-vm; then
  echo "Installing the macOS VM first-boot hook"
  # A private payload carries the hook beside the rest of the stack.
  hook_archive=""
  for candidate in /var/lib/omarchy/macos-vm/repo/omarchy-macos-vm-[0-9]*.pkg.tar.* \
    /boot/efi/omarchy/macos-vm/repo/omarchy-macos-vm-[0-9]*.pkg.tar.*; do
    if [[ -f $candidate && $candidate != *.sig ]]; then
      hook_archive=$candidate
    fi
  done
  if [[ -n $hook_archive ]]; then
    as_root pacman -U --needed --noconfirm "$hook_archive" ||
      echo "Warning: could not install $hook_archive; no macOS VM setup." >&2
  else
    omarchy-pkg-add omarchy-macos-vm ||
      echo "Warning: omarchy-macos-vm is in no repository this Mac uses; no macOS VM setup." >&2
  fi
fi
if omarchy-pkg-present omarchy-macos-vm; then
  as_root systemctl enable omarchy-macos-vm-setup.service >/dev/null 2>&1 ||
    echo "Warning: could not enable omarchy-macos-vm-setup.service" >&2
fi
