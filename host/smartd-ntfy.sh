#!/bin/bash
# Proxmox host: /usr/local/bin/smartd-ntfy.sh.
# smartd calls this when a drive reports a problem (see /etc/smartd.conf, -M exec).
#
# Emergency brake approved by the owner 23/09/2026: a failing disk triggers an extra backup at once,
# unless the failing disk IS the backup drive, where writing more would only stress it.
# Then hands off to the normal smartd handler so nothing is lost.
#
# B8, security review of 28/09/2026: when /mnt/backup was not mounted, the backup drive could not
# be named, and every failing disk was reported as "the backup drive". Now there are three cases:
# another disk (brake), the backup drive, and "can't tell", which says so and starts no backup.
SRC=$(findmnt -no SOURCE /mnt/backup 2>/dev/null)
BACKUP_DISK=""
if [ -n "$SRC" ]; then
  # The disk holding the backup filesystem: its parent if it sits on a partition, else itself.
  BACKUP_DISK=$(lsblk -no PKNAME "$SRC" 2>/dev/null | head -n 1)
  [ -n "$BACKUP_DISK" ] || BACKUP_DISK=$(lsblk -dno KNAME "$SRC" 2>/dev/null | head -n 1)
fi
DEV=$(basename "${SMARTD_DEVICE:-unknown}")
# smartd names an NVMe drive by its controller (nvme0) while lsblk names the disk (nvme0n1).
case "$BACKUP_DISK" in nvme*n[0-9]*) [ "$DEV" = "${BACKUP_DISK%n[0-9]*}" ] && DEV=$BACKUP_DISK ;; esac

if [ -z "$BACKUP_DISK" ]; then
  server-notify red disk "A disk is failing" \
    "Drive $DEV reported: ${SMARTD_MESSAGE:-a fault}" \
    "The backup drive isn't mounted, so no extra backup was started." \
    --you "Order a replacement drive. Ask Claude on home-server which one it is and why the backup drive is missing."
elif [ "$DEV" != "$BACKUP_DISK" ]; then
  systemctl start --no-block backup.service
  server-notify brake disk "A disk is failing" \
    "Drive $DEV reported: ${SMARTD_MESSAGE:-a fault}" \
    "Nothing is lost yet. An extra backup has been started straight away." \
    --you "Order a replacement drive. Ask Claude on home-server which one it is and what's on it."
else
  server-notify red disk "The backup drive is failing" \
    "Drive $DEV reported: ${SMARTD_MESSAGE:-a fault}" \
    "Your files are fine, but the backups are at risk." \
    --you "Order a replacement drive. Ask Claude on home-server what to do in the meantime."
fi

/usr/share/smartmontools/smartd-runner "$@" 2>/dev/null || true
