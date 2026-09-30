#!/bin/bash
# Proxmox host: /usr/local/bin/smartd-ntfy.sh.
# smartd calls this when a drive reports a problem (see /etc/smartd.conf, -M exec).
#
# Emergency brake approved by the owner 23/09/2026: a failing disk triggers an extra backup at once,
# unless the failing disk IS the backup drive, where writing more would only stress it.
# Then hands off to the normal smartd handler so nothing is lost.
BACKUP_DISK=$(lsblk -no PKNAME "$(findmnt -no SOURCE /mnt/backup 2>/dev/null)" 2>/dev/null)
DEV=$(basename "${SMARTD_DEVICE:-unknown}")

if [ -n "$BACKUP_DISK" ] && [ "$DEV" != "$BACKUP_DISK" ]; then
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
