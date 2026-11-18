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

# omarchy-macos-vm, the menu's counterpart of omarchy-windows-vm.
command=$ROOT/bin/omarchy-macos-vm
grep -Fq "'omarchy-macos-vm install'" "$ROOT/default/omarchy/omarchy-menu.jsonc" &&
  grep -Fq "'omarchy-macos-vm remove'" "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "Install and Remove offer macOS beside Windows"
stub omarchy-hw-apple 'exit 0'
printf 'apple,j314s\0apple,t6000\0apple,arm-platform\0' >"$test_tmp/m1"
printf 'apple,j614s\0apple,t6040\0apple,arm-platform\0' >"$test_tmp/m4"
set +e
OMARCHY_APPLE_COMPATIBLE=$test_tmp/m4 PATH="$stub_bin:$PATH" bash "$command" install >"$test_tmp/out" 2>&1
status=$?
set -e
(( status == 1 )) && grep -Fq 'M1 or M2' "$test_tmp/out" || fail "install refuses a Mac after M2" "$(cat "$test_tmp/out")"
PATH="$stub_bin:$PATH" bash "$command" help | grep -Fq 'install' || fail "the command prints its usage"
pass "omarchy-macos-vm install refuses Macs after M2 and is in the menu beside Windows"

# launch: the "macOS" launcher entry. Without a VM it shows omvm's next steps.
state=$test_tmp/state
mkdir -p "$state"
printf 'The one-time macOS step\n\n1. Boot macOS once\n2. omvm ingest\n' >"$state/next-steps.txt"
stub omarchy-notification-send 'printf "notify %s\n" "$*" >>"$TEST_LOG"'
stub omvm 'echo "omvm $*" >>"$TEST_LOG"; [[ $1 != mode || -n ${TEST_VM:-} ]]'
run_launch() {
  : >"$log"
  set +e
  env PATH="$stub_bin:$PATH" TEST_LOG="$log" HOME="$test_tmp/home" OMARCHY_MACOS_VM_STATE="$state" \
    bash "$command" launch >"$test_tmp/out" 2>&1
  status=$?
  set -e
}
run_launch
(( status == 1 )) || fail "launch without a VM fails" "$(cat "$test_tmp/out")"
grep -q "^notify .*macOS VM not set up yet 1. Boot macOS once" "$log" && grep -q -- "--exec .*cat $state/next-steps.txt" "$log" || fail "launch without a VM shows the next steps, and a click opens them all" "$(cat "$log")"
! grep -q '^omvm show' "$log" || fail "launch without a VM does not call omvm show" "$(cat "$log")"
TEST_VM=1 run_launch
(( status == 0 )) && grep -Fxq 'omvm show macos' "$log" || fail "launch brings the VM up with omvm show" "$(cat "$log")"
! grep -q '^notify' "$log" || fail "a working launch sends no notification" "$(cat "$log")"
pass "omarchy-macos-vm launch runs omvm show, or shows the next steps when there is no VM yet"
