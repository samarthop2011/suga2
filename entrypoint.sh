#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_BASE="https://cloud.debian.org/images/cloud/trixie/latest"
IMAGE_NAME="debian-13-genericcloud-amd64.qcow2"
BASE_IMAGE="/data/${IMAGE_NAME}"
VM_DISK="/data/debian13.qcow2"
SEED_DIR="/run/debian-seed"
SEED_ISO="/data/debian13-seed.iso"
PIDFILE="/run/qemu/qemu.pid"

: "${PORT:=8080}"
: "${VM_NAME:=debian13}"
: "${VM_RAM:=2048}"
: "${VM_CPUS:=2}"
: "${VM_DISK_SIZE:=20G}"
: "${VM_USERNAME:=sam}"
: "${TTYD_USERNAME:=sam}"

if [[ -z "${VM_PASSWORD:-}" || "${VM_PASSWORD}" == "ChangeMe-Immediately" ]]; then
  echo "ERROR: Set a strong VM_PASSWORD environment variable in Suga."
  exit 1
fi
if [[ -z "${TTYD_PASSWORD:-}" || "${TTYD_PASSWORD}" == "ChangeMe-Immediately" ]]; then
  echo "ERROR: Set a strong TTYD_PASSWORD environment variable in Suga."
  exit 1
fi

for value in "$VM_RAM" "$VM_CPUS"; do
  [[ "$value" =~ ^[0-9]+$ ]] || { echo "RAM and CPU values must be integers."; exit 1; }
done
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "PORT must be numeric."; exit 1; }

mkdir -p /data /run/qemu "$SEED_DIR"

if [[ ! -s "$BASE_IMAGE" ]]; then
  echo "Downloading official Debian 13 cloud image..."
  curl -fL --retry 5 --retry-delay 2 \
    "$IMAGE_BASE/$IMAGE_NAME" -o "$BASE_IMAGE.tmp"
  mv "$BASE_IMAGE.tmp" "$BASE_IMAGE"
fi

# Verify the downloaded image against Debian's published SHA-512 checksum.
if [[ ! -f "${BASE_IMAGE}.verified" ]]; then
  echo "Verifying Debian cloud image checksum..."
  curl -fL --retry 5 "$IMAGE_BASE/SHA512SUMS" -o /tmp/SHA512SUMS
  expected="$(awk -v f="$IMAGE_NAME" '$2 == f || $2 == "*" f {print $1; exit}' /tmp/SHA512SUMS)"
  [[ -n "$expected" ]] || { echo "Could not find image checksum in SHA512SUMS."; exit 1; }
  printf '%s  %s\n' "$expected" "$BASE_IMAGE" | sha512sum -c -
  touch "${BASE_IMAGE}.verified"
fi

if [[ ! -s "$VM_DISK" ]]; then
  echo "Creating persistent VM disk ($VM_DISK_SIZE)..."
  qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" \
    -o "size=$VM_DISK_SIZE" "$VM_DISK"
fi

# Generate cloud-init data. Password is hashed before it enters the guest.
PASSWORD_HASH="$(openssl passwd -6 "$VM_PASSWORD")"
cat > "$SEED_DIR/user-data" <<EOF
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true
users:
  - name: ${VM_USERNAME}
    groups: [sudo, adm]
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    lock_passwd: false
    passwd: '${PASSWORD_HASH}'
ssh_pwauth: true
disable_root: true
chpasswd:
  expire: false
package_update: true
packages:
  - qemu-guest-agent
  - openssh-server
  - curl
runcmd:
  - systemctl enable --now ssh
  - systemctl enable --now qemu-guest-agent || true
EOF

cat > "$SEED_DIR/meta-data" <<EOF
instance-id: debian13-suga
local-hostname: ${VM_NAME}
EOF

cloud-localds "$SEED_ISO" "$SEED_DIR/user-data" "$SEED_DIR/meta-data"

# Use hardware KVM only when the platform exposes the device to this container.
if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
  ACCEL=(-accel kvm)
  echo "KVM device detected: using hardware acceleration."
else
  ACCEL=(-accel tcg,thread=multi)
  echo "WARNING: /dev/kvm is unavailable. Using slow QEMU software emulation."
  echo "Enable /dev/kvm passthrough in the Suga runtime if the platform permits it."
fi

# Avoid starting a second VM if the persistent data volume survives a restart.
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "A QEMU process already appears to be running."
  exit 1
fi
rm -f "$PIDFILE"

echo "Starting Debian 13 VM..."
qemu-system-x86_64 \
  "${ACCEL[@]}" \
  -machine q35 \
  -cpu max \
  -m "${VM_RAM}M" \
  -smp "$VM_CPUS" \
  -name "$VM_NAME" \
  -drive "file=$VM_DISK,if=virtio,format=qcow2" \
  -drive "file=$SEED_ISO,if=virtio,format=raw,readonly=on" \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -serial tcp:127.0.0.1:4444,server,nowait \
  -display none \
  -no-reboot \
  -pidfile "$PIDFILE" \
  -daemonize

cleanup() {
  if [[ -f "$PIDFILE" ]]; then
    qpid="$(cat "$PIDFILE")"
    kill "$qpid" 2>/dev/null || true
  fi
}
trap cleanup TERM INT

echo "Waiting for VM serial console..."
for _ in $(seq 1 120); do
  if (echo > /dev/tcp/127.0.0.1/4444) >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "Starting password-protected browser terminal on port $PORT."
echo "Guest SSH is forwarded to container port 2222."
exec ttyd -p "$PORT" -c "${TTYD_USERNAME}:${TTYD_PASSWORD}" \
  -t titleFixed="Debian 13 - Suga KVM" \
  socat -,raw,echo=0 TCP:127.0.0.1:4444
