#!/bin/bash
# Proxmox host: /usr/local/sbin/support-watch.sh, every 5 minutes from support-watch.timer.
#
#
# The checks Uptime Kuma cannot do, because they are about the host's own disks. Plain script,
# no AI, so it keeps working if Claude is logged out or Anthropic is down. Alerts only on a
# change of state (fine -> problem, problem -> fine), never on every run.
#
# Emergency brake, approved by the owner 23/09/2026: media disk 97% full -> stop the app that writes to it.
# Brakes may only stop or pause, never delete. Resuming is left to the owner.
#
# The ransomware check (lots of hub files changing at once) is in WATCH-ONLY mode: it logs the
# numbers and does nothing, until a week of normal activity shows where the line should be.
# A brake that fires on an ordinary busy evening would cut the owner off their own files.
set -uo pipefail
KUMA_URL=${KUMA_URL:-http://uptime-kuma.lan:3001}   # your Uptime Kuma address
BRAKE_CT=${BRAKE_CT:-}; BRAKE_APP=${BRAKE_APP:-}   # container and Docker app the brake stops (blank = brake off)
S=/var/lib/support-watch; mkdir -p "$S"
LOG=/var/log/support-watch.log
log() { echo "$(date '+%F %T')  $*" >> "$LOG"; }
get() { cat "$S/$1" 2>/dev/null || echo ok; }
put() { echo "$2" > "$S/$1"; }
use() { df --output=pcent "$1" 2>/dev/null | tail -1 | tr -dc 0-9; }

# --- drives mounted ---
for m in hub media backup; do
  case $m in hub) what="The shared file drive"; eff="Claude can't read or write anything, and your PC and Mac lose the hub.";;
             media) what="The media drive"; eff="Jellyfin has no films to play.";;
             backup) what="The backup drive"; eff="Tonight's backup won't happen.";; esac
  if mountpoint -q "/mnt/$m"; then
    [ "$(get mount-$m)" = down ] && { server-notify green disk "$what is back" "The drive is mounted again."; log "mount $m back"; }
    put mount-$m ok
  else
    [ "$(get mount-$m)" = ok ] && { server-notify red disk "$what isn't mounted" "$eff" --you "Ask Claude on home-server to look at it."; log "mount $m DOWN"; }
    put mount-$m down
  fi
done

# --- disk space: warn at 90%, brake the media disk at 97% ---
space() {  # key, path, friendly name
  local p; p=$(use "$2"); [ -n "$p" ] || return
  local was; was=$(get space-$1)
  if [ "$1" = media ] && [ "$p" -ge 97 ]; then
    if [ "$was" != brake ]; then
      [ -n "$BRAKE_CT" ] && [ -n "$BRAKE_APP" ] && pct exec "$BRAKE_CT" -- docker stop "$BRAKE_APP" >/dev/null 2>&1
      server-notify brake disk "Media disk paused" "The media disk is ${p}% full." \
        "Nothing is lost. The app writing to it was stopped so the disk can't fill up and damage files." \
        --you "Free some space, then ask Claude to restart it."
      log "BRAKE media ${p}% - writer stopped"; put space-$1 brake
    fi
  elif [ "$p" -ge 90 ]; then
    [ "$was" = ok ] && { server-notify amber disk "$3 is ${p}% full" "It has less than a tenth of its space left." --you "Free some space, or ask Claude what's using it."; log "space $1 ${p}%"; put space-$1 warn; }
  elif [ "$p" -le 85 ]; then
    [ "$was" = brake ] && server-notify green disk "$3 has room again" "It's now ${p}% full." "The app that was stopped is still paused." --you "Ask Claude to restart it when you're ready."
    [ "$was" != ok ] && log "space $1 back to ${p}%"
    put space-$1 ok
  fi
}
space root   /           "The server's system disk"
space hub    /mnt/hub    "The hub drive"
space media  /mnt/media  "The media disk"
space backup /mnt/backup "The backup drive"

# The container storage pool fills silently and freezes every container when it's full.
pool=$(LVM_SUPPRESS_FD_WARNINGS=1 lvs --noheadings -o data_percent,lv_attr vmdata 2>/dev/null | awk '$2 ~ /^t/ {print int($1); exit}')
if [ -n "$pool" ]; then
  if [ "$pool" -ge 90 ] && [ "$(get pool)" = ok ]; then
    server-notify amber disk "Container storage is ${pool}% full" "When it's full, every app on the server freezes." --you "Ask Claude what's using it."
    log "pool ${pool}%"; put pool warn
  elif [ "$pool" -le 85 ]; then put pool ok; fi
fi

# --- memory starvation: a container at its memory cap thrashes instead of crashing ---
# Added 25/09/2026. CT 111 sat at its 4 GB cap all day, re-reading itself from disk, and the
# phone could not reach Claude. Nothing crashed, so no other check noticed. memory.current is
# useless here (page cache always fills it); memory pressure is the real signal: the share of
# the last 5 minutes the container spent stalled waiting for memory.
for cg in /sys/fs/cgroup/lxc/*/; do
  id=$(basename "$cg"); [ -f "$cg/memory.pressure" ] || continue
  pr=$(awk '/^some/ {split($4,a,"="); print int(a[2])}' "$cg/memory.pressure")
  name=$(awk '/^hostname:/ {print $2}' "/etc/pve/lxc/$id.conf" 2>/dev/null)
  if [ "${pr:-0}" -ge 20 ]; then
    [ "$(get mem-$id)" = ok ] && { server-notify amber server "${name:-CT $id} is out of memory" "It has spent ${pr}% of the last 5 minutes stalled, so anything on it will be slow or not answer." --you "Ask Claude what's using its memory."; log "mem $id pressure ${pr}%"; put mem-$id warn; }
  elif [ "${pr:-0}" -le 5 ]; then
    [ "$(get mem-$id)" = warn ] && { server-notify green server "${name:-CT $id} has memory again" "It's running normally."; log "mem $id back"; }
    put mem-$id ok
  fi
done

# --- disk swamped: the whole host waiting on disk, whatever the cause ---
io=$(awk '/^some/ {split($4,a,"="); print int(a[2])}' /proc/pressure/io)
if [ "${io:-0}" -ge 50 ]; then
  [ "$(get io)" = ok ] && { server-notify amber server "The server is struggling" "It has spent ${io}% of the last 5 minutes waiting on its disks, so everything on it is slow." --you "Ask Claude what's hammering the disks."; log "io pressure ${io}%"; put io warn; }
elif [ "${io:-0}" -le 20 ]; then
  [ "$(get io)" = warn ] && { server-notify green server "The server has calmed down" "Disk waits are back to normal."; log "io back"; }
  put io ok
fi

# --- who watches the watcher: Uptime Kuma is 1st line, and it can't report itself down ---
if curl -fsS -m 10 -o /dev/null $KUMA_URL/api/entry-page 2>/dev/null; then
  [ "$(get kuma)" = down ] && { server-notify green monitor "Uptime Kuma is back" "The server is being watched again."; log "kuma back"; }
  put kuma ok
else
  [ "$(get kuma)" = ok ] && { server-notify red monitor "Uptime Kuma is down" "Nothing is watching your apps, so faults won't be spotted or sent to Claude." --you "Ask Claude on home-server to look at it."; log "kuma DOWN"; }
  put kuma down
fi

# --- ransomware pattern: WATCH-ONLY, logging numbers until tuned ---
if mountpoint -q /mnt/hub; then
  n=$(find /mnt/hub -xdev \( -name .git -o -path '*/history' \) -prune -o -type f -mmin -5 -print 2>/dev/null | wc -l)
  echo "$(date '+%F %T') $n" >> "$S/hub-changes.log"
  tail -n 5000 "$S/hub-changes.log" > "$S/hub-changes.tmp" && mv "$S/hub-changes.tmp" "$S/hub-changes.log"
fi

[ -f "$LOG" ] && tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
exit 0
