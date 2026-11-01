#!/usr/bin/env bash

# Mounts this node's EBS data volume before Nomad starts and exposes it as a
# Nomad host volume. A blank volume is formatted; a volume with any existing
# filesystem or partition table is never touched, so a replacement instance
# picks up the same data. Nomad requires the mount, so it does not start and
# write to the root disk when the volume is missing.

set -Eeuo pipefail

readonly VOLUME_ID="${volume_id}"
readonly MOUNT_PATH="${mount_path}"
readonly DEVICE="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${replace(volume_id, "-", "")}"
readonly ATTACH_TIMEOUT=900

log() {
  printf '%s [%s] data_volume: %s\n' "$(date -u +%FT%TZ)" "$1" "$2" >&2
}

trap 'log ERROR "failed at line $LINENO"' ERR

install -d -m 0755 /etc/nomad.d /etc/systemd/system/nomad.service.d "$MOUNT_PATH"

cat >/etc/systemd/system/nomad.service.d/data-volume.conf <<UNIT
[Unit]
RequiresMountsFor=$MOUNT_PATH
UNIT

cat >/etc/nomad.d/node.hcl <<'NOMAD_CONFIG'
name = ${jsonencode(node_name)}

client {
  meta {
    static_node = ${jsonencode(node_key)}
  }

  host_volume ${jsonencode(host_volume)} {
    path      = ${jsonencode(mount_path)}
    read_only = false
  }
}
NOMAD_CONFIG

# The volume is attached after the instance starts.
deadline=$((SECONDS + ATTACH_TIMEOUT))
until [[ -e "$DEVICE" ]]; do
  if ((SECONDS >= deadline)); then
    log ERROR "volume $VOLUME_ID not attached after $${ATTACH_TIMEOUT}s"
    exit 1
  fi
  sleep 5
done
udevadm settle

# blkid -p exits 2 only when it finds no signature at all.
rc=0
blkid -p "$DEVICE" >/dev/null 2>&1 || rc=$?
if ((rc == 2)); then
  log INFO "formatting blank volume $VOLUME_ID"
  mkfs.xfs -L nomad-data "$DEVICE"
elif ((rc != 0)); then
  log ERROR "blkid failed on $DEVICE with exit code $rc"
  exit 1
fi

uuid=$(blkid -s UUID -o value "$DEVICE")
if ! grep -q "^UUID=$uuid " /etc/fstab; then
  sed -i "\| $MOUNT_PATH |d" /etc/fstab
  printf 'UUID=%s %s xfs defaults,nofail 0 2\n' "$uuid" "$MOUNT_PATH" >>/etc/fstab
fi
systemctl daemon-reload
mountpoint -q "$MOUNT_PATH" || mount "$MOUNT_PATH"
log INFO "mounted $VOLUME_ID at $MOUNT_PATH"
