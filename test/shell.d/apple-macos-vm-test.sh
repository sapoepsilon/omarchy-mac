#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/macos-vm.sh"
grep -Fq 'apple/macos-vm.sh' "$ROOT/install/hardware/all.sh" ||
  fail "the macOS VM leaf runs during hardware setup"
pass "the macOS VM leaf is wired into hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin=$test_tmp/bin
log=$test_tmp/calls
mkdir -p "$stub_bin"
printf 'apple,j314s\0apple,arm-platform\0' >"$test_tmp/compatible"
printf 'raspberrypi,4-model-b\0' >"$test_tmp/pi"

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$stub_bin/$1"; chmod +x "$stub_bin/$1"; }
stub uname 'echo aarch64'
stub omarchy-pkg-missing '[[ ! -e $TEST_INSTALLED ]]'
stub omarchy-pkg-present '[[ -e $TEST_INSTALLED ]]'
stub omarchy-pkg-add 'echo "pkg-add $*" >>"$TEST_LOG"; touch "$TEST_INSTALLED"'
stub sudo '"$@"'
stub systemctl 'echo "systemctl $*" >>"$TEST_LOG"'
stub pacman 'echo "pacman $*" >>"$TEST_LOG"; touch "$TEST_INSTALLED"'

run_leaf() {
  : >"$log"
  rm -f "$test_tmp/installed"
  env PATH="$stub_bin:$PATH" TEST_LOG="$log" TEST_INSTALLED="$test_tmp/installed" \
    OMARCHY_APPLE_COMPATIBLE="${COMPATIBLE:-$test_tmp/compatible}" \
    OMARCHY_MACOS_VM_MARKER="$test_tmp/etc/omarchy/macos-vm.enabled" \
    bash -c 'source "$1"' _ "$leaf"
}

rm -rf "$test_tmp/etc"
run_leaf
[[ ! -s $log ]] || fail "without the request nothing is installed" "$(cat "$log")"
pass "without /etc/omarchy/macos-vm.enabled the leaf does nothing"

OMARCHY_MACOS_VM=1 run_leaf
grep -Fq '"requested_by":"install.sh"' "$test_tmp/etc/omarchy/macos-vm.enabled" ||
  fail "OMARCHY_MACOS_VM=1 writes the request"
grep -Fxq 'pkg-add omarchy-macos-vm' "$log" || fail "the hook package is installed" "$(cat "$log")"
grep -Fxq 'systemctl enable omarchy-macos-vm-setup.service' "$log" || fail "its service is enabled" "$(cat "$log")"
pass "a request installs omarchy-macos-vm and enables its setup service"

COMPATIBLE=$test_tmp/pi run_leaf
[[ ! -s $log ]] || fail "a non-Apple aarch64 board is left alone" "$(cat "$log")"
pass "only Apple Silicon Macs get the macOS VM hook"
