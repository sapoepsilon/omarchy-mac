#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The two setup leaves and first run call the platform's own setup through the
# real dispatcher: a Mac fixture with omarchy-mac's entrypoints, and x86.

hardware_leaf="$ROOT/install/hardware/platform-setup.sh"
user_leaf="$ROOT/install/user/platform-setup.sh"

require_platform_fixtures "platform setup on platform fixtures"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fake_platform "$tmp/apple" aarch64-apple
fake_platform "$tmp/x86" x86

lifecycle=$tmp/lifecycle
mkdir -p "$lifecycle/usr/lib/omarchy/mac" "$lifecycle/usr/lib/omarchy/mac-boot"
for entry in mac/setup-system mac/setup-user mac-boot/setup-boot; do
  operation=${entry#*/}
  cat >"$lifecycle/usr/lib/omarchy/$entry" <<SH
#!/bin/bash
{ printf '%s' "$operation"; (( \$# == 0 )) || printf ' %s' "\$@"; echo; } >>"$tmp/ran"
[[ ! -e $tmp/fail && ! -e $tmp/fail-$operation ]]
SH
  chmod 755 "$lifecycle/usr/lib/omarchy/$entry"
done
chmod -R go-w "$lifecycle"

# Sources a leaf as run_logged does, on a platform fixture.
leaf() {
  local platform=$1 script=$2
  shift 2
  rm -f "$tmp/ran"
  env "$@" OMARCHY_PROC_ROOT="$tmp/$platform/proc" OMARCHY_LIFECYCLE_ROOT="$lifecycle" \
    PATH="$tmp/$platform/bin:$ROOT/bin:$PATH" bash -eE -c 'source "$1"' bash "$script" >"$tmp/output" 2>&1
}

# ── system setup ─────────────────────────────────────────────────────────────

leaf apple "$hardware_leaf" || fail "apple: the system setup leaf runs" "$(cat "$tmp/output")"
[[ $(cat "$tmp/ran") == $'setup-boot\nsetup-system' ]] || fail "apple: an install or rerun runs setup-boot, then setup-system, with no argument" "$(cat "$tmp/ran")"
leaf apple "$hardware_leaf" OMARCHY_IMAGE_DEFERRED_HARDWARE=1 || fail "apple: the system setup leaf runs on an image's first boot"
[[ $(cat "$tmp/ran") == $'setup-boot image-first-boot\nsetup-system image-first-boot' ]] ||
  fail "apple: an image's first boot tells setup-boot and setup-system so" "$(cat "$tmp/ran")"
touch "$tmp/fail-setup-system"
if leaf apple "$hardware_leaf"; then
  fail "apple: a failed setup-system fails the leaf"
fi
[[ $(cat "$tmp/ran") == $'setup-boot\nsetup-system' ]] || fail "apple: setup-system ran after the boot setup and failed" "$(cat "$tmp/ran")"
rm -f "$tmp/fail-setup-system"
touch "$tmp/fail-setup-boot"
if leaf apple "$hardware_leaf"; then
  fail "apple: a failed setup-boot fails the leaf"
fi
[[ $(cat "$tmp/ran") == "setup-boot" ]] || fail "apple: setup-system waits for a boot setup that failed" "$(cat "$tmp/ran")"
rm -f "$tmp/fail-setup-boot"
mv "$lifecycle/usr/lib/omarchy/mac-boot/setup-boot" "$tmp/setup-boot.saved"
if leaf apple "$hardware_leaf"; then
  fail "apple: a Mac whose boot package lacks setup-boot fails the leaf instead of skipping its boot setup"
fi
grep -q "setup-boot on aarch64-apple needs omarchy-mac-boot" "$tmp/output" || fail "apple: the failure names the boot package" "$(cat "$tmp/output")"
mv "$tmp/setup-boot.saved" "$lifecycle/usr/lib/omarchy/mac-boot/setup-boot"
pass "apple: the system setup leaf runs omarchy-mac-boot's setup-boot, then omarchy-mac's setup-system, says when it is an image's first boot, and fails with either"

touch "$tmp/fail"
leaf x86 "$hardware_leaf" OMARCHY_IMAGE_DEFERRED_HARDWARE=1 || fail "x86: the system setup leaf is a no-op" "$(cat "$tmp/output")"
[[ ! -e $tmp/ran && ! -s $tmp/output ]] || fail "x86: the system setup leaf runs nothing and says nothing" "$(cat "$tmp/output")"
rm -f "$tmp/fail"
pass "x86: the system setup leaf is a no-op, even with Mac entrypoints on disk"

# A requested macOS VM must fail finalization if its hook cannot be installed
# or enabled; a warning followed by success would silently drop the request.
vm_bin=$tmp/vm-bin
mkdir -p "$vm_bin"
cat >"$vm_bin/omarchy-pkg-missing" <<'SH'
#!/bin/bash
[[ ! -e $VM_INSTALLED ]]
SH
cat >"$vm_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ -e $VM_INSTALLED ]]
SH
cat >"$vm_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
[[ ${VM_FAIL:-} != "install" ]] || exit 1
[[ ${VM_FAIL:-} == "absent" ]] || touch "$VM_INSTALLED"
SH
cat >"$vm_bin/systemctl" <<'SH'
#!/bin/bash
[[ ${VM_FAIL:-} != "enable" ]] || exit 1
touch "$VM_ENABLED"
SH
printf '#!/bin/bash\n"$@"\n' >"$vm_bin/sudo"
chmod +x "$vm_bin"/*

vm_leaf() {
  rm -f "$tmp/vm-installed" "$tmp/vm-enabled" "$tmp/vm-request"
  env OMARCHY_PROC_ROOT="$tmp/apple/proc" \
    PATH="$vm_bin:$tmp/apple/bin:$ROOT/bin:$PATH" OMARCHY_MACOS_VM=1 \
    OMARCHY_MACOS_VM_MARKER="$tmp/vm-request" VM_INSTALLED="$tmp/vm-installed" \
    VM_ENABLED="$tmp/vm-enabled" VM_FAIL="$1" \
    bash -eE -c 'source "$1"' bash "$ROOT/install/hardware/apple/macos-vm.sh" >"$tmp/output" 2>&1
}

vm_leaf "" || fail "macOS VM request installs and enables the hook" "$(cat "$tmp/output")"
[[ -f $tmp/vm-request && -f $tmp/vm-enabled ]] || fail "macOS VM request remains recorded and enabled"
for stage in install absent enable; do
  if vm_leaf "$stage"; then
    fail "macOS VM $stage failure must fail the hardware leaf"
  fi
  [[ -f $tmp/vm-request && ! -f $tmp/vm-enabled ]] || fail "macOS VM $stage failure preserves the request without enabling an incomplete hook"
done
pass "macOS VM hook installation and enablement failures fail the requested setup"

# ── user setup ───────────────────────────────────────────────────────────────

leaf apple "$user_leaf" OMARCHY_IMAGE_ROOT="$tmp/booted" || fail "apple: the user setup leaf runs" "$(cat "$tmp/output")"
[[ $(cat "$tmp/ran") == "setup-user" ]] || fail "apple: the user setup leaf runs setup-user" "$(cat "$tmp/ran" 2>/dev/null)"
touch "$tmp/fail"
if leaf apple "$user_leaf" OMARCHY_IMAGE_ROOT="$tmp/booted"; then
  fail "apple: a failed setup-user fails finalization's leaf"
fi
rm -f "$tmp/fail"

mkdir -p "$tmp/image/var/lib/omarchy/image"
: >"$tmp/image/var/lib/omarchy/image/target"
leaf apple "$user_leaf" OMARCHY_IMAGE_ROOT="$tmp/image" || fail "apple: the user setup leaf succeeds in an image build"
[[ ! -e $tmp/ran && $(cat "$tmp/output") == *"waits for first run on the machine"* ]] ||
  fail "apple: an image build leaves the platform's user setup to first run" "$(cat "$tmp/output")"
pass "apple: the user setup leaf runs omarchy-mac's setup-user, fails with it, and waits for the machine in an image build"

touch "$tmp/fail"
leaf x86 "$user_leaf" OMARCHY_IMAGE_ROOT="$tmp/booted" || fail "x86: the user setup leaf is a no-op" "$(cat "$tmp/output")"
[[ ! -e $tmp/ran && ! -s $tmp/output ]] || fail "x86: the user setup leaf runs nothing and says nothing" "$(cat "$tmp/output")"
rm -f "$tmp/fail"
pass "x86: the user setup leaf is a no-op, even with Mac entrypoints on disk"

# ── first run ────────────────────────────────────────────────────────────────

# First run on the machine runs setup-user once the session is up. Its failure
# leaves first run pending for the next login, as a failed finalization does.
first_bin=$tmp/first-bin
first_root=$tmp/omarchy
mkdir -p "$first_bin" "$first_root/install/user/first-run" "$tmp/home"
cat >"$first_bin/omarchy-done" <<'SH'
#!/bin/bash
case "$1:$2" in
  check:first-run-user) exit 1 ;;
  mark:first-run-user) touch "$FIRST_RUN_MARKER" ;;
esac
SH
for helper in omarchy-provision-user omarchy-hook-install omarchy-notification-wait; do
  printf '#!/bin/bash\nexit 0\n' >"$first_bin/$helper"
done
chmod +x "$first_bin"/*
for script in "$ROOT"/install/user/first-run/*.sh; do
  printf 'exit 0\n' >"$first_root/install/user/first-run/${script##*/}"
done

first_run() {
  local platform=$1
  rm -f "$tmp/ran" "$tmp/first-run-marker" "$tmp/home/.local/state/omarchy/first-run.log"
  HOME="$tmp/home" OMARCHY_PATH="$first_root" FIRST_RUN_MARKER="$tmp/first-run-marker" \
    OMARCHY_PROC_ROOT="$tmp/$platform/proc" OMARCHY_LIFECYCLE_ROOT="$lifecycle" \
    PATH="$first_bin:$tmp/$platform/bin:$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-provision-first-run" >"$tmp/output" 2>&1
}

first_run apple || fail "apple: first run finishes" "$(cat "$tmp/output")"
[[ $(cat "$tmp/ran") == "setup-user" && -e $tmp/first-run-marker ]] ||
  fail "apple: first run runs setup-user and completes" "$(cat "$tmp/ran" 2>/dev/null)"
touch "$tmp/fail"
first_run apple || fail "apple: first run with a failing setup-user still runs its other steps"
[[ ! -e $tmp/first-run-marker ]] || fail "apple: a failed setup-user keeps first run pending"
grep -q "Failed: run the platform's user setup" "$tmp/home/.local/state/omarchy/first-run.log" ||
  fail "apple: first run logs the failed platform setup" "$(cat "$tmp/home/.local/state/omarchy/first-run.log")"
first_run x86 || fail "x86: first run finishes"
[[ ! -e $tmp/ran && -e $tmp/first-run-marker ]] || fail "x86: first run runs no platform setup and completes"
rm -f "$tmp/fail"
pass "first run runs the platform's user setup, and a failure keeps first run pending"
