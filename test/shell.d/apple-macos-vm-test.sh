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

# The rest of omarchy-macos-vm against stubbed omvm, virsh, hyprctl and gum.
# State: $vm/exists (omvm virt ran), $vm/state (libvirt's domstate), $vm/windows
# (how many more hyprctl clients calls still see the VM's window).
state=$test_tmp/state
vm=$test_tmp/vm
home=$test_tmp/home
images=$home/.local/share/omvm/images
kvm_param=$test_tmp/emulate_nisv_ldst
mkdir -p "$state" "$vm"
printf 'The one-time macOS step\n\n1. Boot macOS once\n2. omvm ingest\n' >"$state/next-steps.txt"
stub omarchy-notification-send 'printf "notify %s\n" "$*" >>"$TEST_LOG"'
stub omarchy-pkg-add 'echo "pkg-add $*" >>"$TEST_LOG"'
stub omarchy-pkg-remove 'echo "pkg-remove $*" >>"$TEST_LOG"'
stub omvm 'echo "omvm $* CPUS=${CPUS:-} RAM_GIB=${RAM_GIB:-}" >>"$TEST_LOG"
case $1 in
  mode) [[ -e $TEST_VMDIR/exists ]] && echo remote ;;
  start) echo running >"$TEST_VMDIR/state" ;;
  stop) echo "shut off" >"$TEST_VMDIR/state" ;;
  ssh) [[ -z ${TEST_SSH_DOWN:-} ]] ;;
  setup) mkdir -p "$OMVM_IMAGES/b-v0" ;;
  ingest) mkdir -p "$OMVM_IMAGES/b-restore" && touch "$OMVM_IMAGES/b-restore/.ingested" ;;
  virt) [[ $2 == rm ]] && rm -f "$TEST_VMDIR/exists" || { touch "$TEST_VMDIR/exists"; echo "shut off" >"$TEST_VMDIR/state"; } ;;
esac'
stub virsh 'echo "virsh $*" >>"$TEST_LOG"; cat "$TEST_VMDIR/state" 2>/dev/null'
stub hyprctl 'echo "hyprctl $*" >>"$TEST_LOG"
if [[ $1 == clients ]]; then
  left=$(cat "$TEST_VMDIR/windows" 2>/dev/null || echo 0)
  if (( left > 0 )); then echo $((left - 1)) >"$TEST_VMDIR/windows"; echo "[{\"class\":\"vncviewer\",\"address\":\"0xabc\"}]"; else echo "[]"; fi
fi'
stub gum 'echo "gum $*" >>"$TEST_LOG"
case $1 in
  choose) cat >/dev/null; echo "${TEST_RAM:-16G}" ;;
  input) case "$*" in *--password*) echo "${TEST_PASSWORD:-}" ;; *"CPU cores"*) echo "${TEST_CORES:-6}" ;; *) echo "${TEST_ACCOUNT:-alice}" ;; esac ;;
  confirm) answers=$(cat "$TEST_VMDIR/confirm-rest" 2>/dev/null); [[ -n $answers ]] || answers=${TEST_CONFIRM:-y}; first=${answers:0:1}; echo "${answers:1}" >"$TEST_VMDIR/confirm-rest"; [[ $first == y ]] ;;
  style) shift; printf "%s\n" "$@" ;;
esac'

run_cmd() {
  : >"$log"
  rm -f "$vm/confirm-rest"
  set +e
  env PATH="$stub_bin:$PATH" TEST_LOG="$log" TEST_VMDIR="$vm" TEST_INSTALLED="$test_tmp/installed" \
    HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share" \
    OMVM_IMAGES="$images" OMARCHY_MACOS_VM_STATE="$state" OMARCHY_MACOS_VM_MARKER="$test_tmp/etc/omarchy/macos-vm.enabled" \
    OMARCHY_MACOS_VM_KVM_PARAM="$kvm_param" OMARCHY_APPLE_COMPATIBLE="$test_tmp/m1" OMARCHY_MACOS_VM_REQUIRED_GB=0 \
    OMARCHY_MACOS_VM_POLL=0 OMARCHY_MACOS_VM_BOOT_TIMEOUT=6 \
    bash "$command" "$@" >"$test_tmp/out" 2>&1
  status=$?
  set -e
}
reset_vm() { rm -rf "$vm" "$home" "$state/vmxfer-ready" "$kvm_param"; mkdir -p "$vm"; touch "$state/done" "$test_tmp/installed"; }

# launch without a VM: the next steps in a notification, a click opens them all.
reset_vm
run_cmd launch
(( status == 1 )) || fail "launch without a VM fails" "$(cat "$test_tmp/out")"
grep -q "^notify .*macOS VM not set up yet 1. Boot macOS once" "$log" && grep -q -- "--exec .*cat $state/next-steps.txt" "$log" ||
  fail "launch without a VM shows the next steps, and a click opens them all" "$(cat "$log")"
! grep -q '^omvm show' "$log" || fail "launch without a VM does not call omvm show" "$(cat "$log")"
touch "$state/vmxfer-ready" "$kvm_param"
run_cmd launch
grep -q "^notify .*omarchy-macos-vm create" "$log" && grep -q -- "--exec .*'omarchy-macos-vm create'" "$log" ||
  fail "launch with the restored VM on VMXFER offers create" "$(cat "$log")"
pass "launch without a VM shows what is next (the macOS step, or create once VMXFER has the VM)"

# launch: notify, start, wait for SSH, show, fullscreen, wait for the window, stop.
reset_vm
touch "$vm/exists"; echo "shut off" >"$vm/state"; echo 3 >"$vm/windows"
run_cmd launch
(( status == 0 )) || fail "launch succeeds" "$(cat "$test_tmp/out")"
grep -q '^notify macOS VM Starting macOS VM' "$log" || fail "launch says it is starting" "$(cat "$log")"
order=$(grep -oE '^(omvm (start|ssh|show|stop)|hyprctl dispatch)' "$log" | uniq | tr '\n' ',')
[[ $order == "omvm start,omvm ssh,omvm show,hyprctl dispatch,omvm stop," ]] ||
  fail "launch starts, waits for SSH, shows, goes fullscreen, then stops when the window closes" "$order"
grep -Fq 'Window closed. Stopping macOS VM...' "$test_tmp/out" && grep -Fq 'macOS VM stopped.' "$test_tmp/out" ||
  fail "launch says it stops the VM" "$(cat "$test_tmp/out")"
echo running >"$vm/state"; echo 3 >"$vm/windows"
run_cmd launch --keep-alive
! grep -q '^omvm start' "$log" && ! grep -q '^omvm stop' "$log" && grep -Fq 'macOS VM is still running.' "$test_tmp/out" ||
  fail "launch --keep-alive leaves a running VM running" "$(cat "$log"; cat "$test_tmp/out")"
pass "omarchy-macos-vm launch starts the VM, waits for it, opens it fullscreen and stops it on close unless --keep-alive"

# install: the wizard's choices are saved where omvm reads them.
reset_vm
run_cmd install
(( status == 0 )) || fail "install succeeds" "$(cat "$test_tmp/out")"
grep -q '^gum choose .*RAM' "$log" && grep -q '^gum input .*CPU cores' "$log" && grep -q '^gum confirm .*Proceed' "$log" ||
  fail "install asks for RAM, cores and confirmation" "$(cat "$log")"
grep -Fxq 'RAM_GIB=16' "$home/.config/omarchy/macos-vm.conf" && grep -Fxq 'CPUS=6' "$home/.config/omarchy/macos-vm.conf" ||
  fail "install saves RAM and cores" "$(cat "$home/.config/omarchy/macos-vm.conf" 2>&1)"
grep -Fxq 'OMVM_GUEST_USER=alice' "$home/.config/omvm/gui.env" || fail "install saves the guest account for omvm"
grep -Fxq 'Exec=uwsm app -- omarchy-macos-vm launch' "$home/.local/share/applications/macos-vm.desktop" || fail "install adds the launcher entry"
grep -q '^notify .*one step in macOS' "$log" && grep -Fq 'runs at the next Omarchy login' "$test_tmp/out" ||
  fail "without the restored VM install tells the macOS step and that the rest follows at login" "$(cat "$test_tmp/out")"
! grep -q '^omvm \(ingest\|setup\|virt\)' "$log" || fail "without the restored VM nothing is created" "$(cat "$log")"
TEST_CONFIRM=n run_cmd install
(( status == 1 )) && grep -Fq 'Installation cancelled by user' "$test_tmp/out" || fail "a declined summary cancels"
pass "omarchy-macos-vm install asks RAM, cores, account and confirmation, saves them, and stages the macOS step"

# create: ingest; on the stock kernel stop and ask for the side kernel; then setup + virt.
reset_vm
mkdir -p "$home/.config/omarchy"; printf 'RAM_GIB=32\nCPUS=4\n' >"$home/.config/omarchy/macos-vm.conf"
touch "$state/vmxfer-ready"
run_cmd create
(( status == 2 )) && grep -q '^omvm ingest' "$log" && ! grep -q '^omvm setup' "$log" &&
  grep -q '^notify .*reboot to finish' "$log" || fail "create on the stock kernel ingests and asks for the side kernel" "$(cat "$log")"
touch "$kvm_param" "$images/Xcode.dmg"
run_cmd create
(( status == 0 )) || fail "create on the side kernel succeeds" "$(cat "$test_tmp/out")"
! grep -q '^omvm ingest' "$log" && grep -q '^omvm setup --xcode' "$log" && grep -q '^omvm virt macos CPUS=4 RAM_GIB=32' "$log" ||
  fail "create runs setup --xcode, then virt with the saved RAM and cores" "$(cat "$log")"
[[ -s $home/.local/state/omarchy-macos-vm/vm-created ]] && grep -q '^notify macOS VM is ready' "$log" || fail "create says the VM is ready"
run_cmd install
grep -q '^omvm virt macos CPUS=6 RAM_GIB=16' "$log" && ! grep -q '^gum input .*account' "$log" ||
  fail "install on an existing VM redefines it with the new settings" "$(cat "$log")"
pass "omarchy-macos-vm create ingests, waits for the side kernel, then sets up and defines the VM"

# status, stop and remove.
echo running >"$vm/state"
run_cmd status
(( status == 0 )) && grep -Fq 'macOS VM Status: RUNNING' "$test_tmp/out" || fail "status shows a running VM" "$(cat "$test_tmp/out")"
run_cmd stop
grep -q '^omvm stop macos' "$log" && grep -Fq 'macOS VM stopped.' "$test_tmp/out" || fail "stop stops the VM"
run_cmd status
grep -Fq 'macOS VM is stopped (status: shut off)' "$test_tmp/out" || fail "status shows a stopped VM" "$(cat "$test_tmp/out")"
TEST_CONFIRM=n run_cmd remove
(( status == 1 )) && [[ -e $vm/exists ]] && grep -q '^gum confirm --default=false' "$log" || fail "remove defaults to No and removes nothing"
TEST_CONFIRM=yn run_cmd remove
(( status == 0 )) && grep -q '^omvm virt rm --yes macos' "$log" && grep -q '^pkg-remove omvm' "$log" && [[ -d $images ]] ||
  fail "remove takes the VM out of libvirt and the stack off, keeping guest images" "$(cat "$log"; cat "$test_tmp/out")"
[[ ! -e $home/.local/share/applications/macos-vm.desktop ]] || fail "remove deletes the launcher entry"
run_cmd status
(( status == 1 )) && grep -Fq 'macOS VM not configured.' "$test_tmp/out" || fail "status without a VM says so"
pass "omarchy-macos-vm status, stop and remove (confirm defaults to No, images kept) match the Windows VM"
