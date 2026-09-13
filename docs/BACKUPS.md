# ZFS Backup Architecture Documentation

## Overview

This document describes the backup architecture implemented on the NAS (Proxmox bare metal, `pve02`) using ZFS, Sanoid, and Syncoid.

Architecture goal:

- Snapshot-based backups on primary storage
- Replication of selected datasets to external USB SSD
- Clean separation of snapshot management and replication
- Safe operation even if USB disk is disconnected

> **⚠️ KNOWN ISSUE / TODO (added 2026-07-25):**
> The `pond` pool does **not** currently auto-import on boot, even when the USB disk is physically connected. This was discovered after `pond` sat un-imported for ~70 days (last successful replication: 2026-05-16), during which all four replication jobs below silently no-op'd every day without any error or alert. All datasets have since been manually caught up (see Section 5.1).
>
> **Fix needed:** `pond` should import automatically both (a) on boot when the USB disk is already connected, and (b) whenever the USB disk is hot-plugged later. Planned approach: a udev rule (matching the T7's `ID_SERIAL`) triggering a oneshot systemd service that runs `zpool import -d /dev/disk/by-id pond` idempotently, ordered around `zfs-import.target`/`systemd-udev-settle.service` so it also fires during boot coldplug, not just live hotplug. Not yet implemented — tracked here until done.
>
> **Also needed:** some form of alerting when a scheduled replication run skips because `pond` isn't available, since the current script fails silently (see Section 3.1). Without this, a repeat of the same issue could go unnoticed indefinitely.

---

# 1. Storage Layout

## Primary Pool

Pool name: `tank`
Mountpoint: `/tank`

Relevant datasets under `tank`:

```
tank/backups
tank/backups/apps/{grist,homarr,keycloak,lidarr,mathesar,memos,n8n,prowlarr,radarr,sabnzbd,sonarr,stash,vaultwarden}
tank/media
tank/media/{audiobooks,docs,downloads,immich,movies,music,share,shows,videos}
```

Snapshots are managed by Sanoid, configured in `/etc/sanoid/sanoid.conf`:

```
[tank/media]
    use_template = media
    recursive = yes

[template_media]
    hourly = 24
    daily = 7
    weekly = 4
    monthly = 3
    autosnap = yes
    autoprune = yes

[tank/backups]
    use_template = backups
    recursive = yes

[template_backups]
    daily = 7
    weekly = 4
    monthly = 3
    autosnap = yes
    autoprune = yes
```

Note: only `tank/backups` and three specific children of `tank/media` (see Section 3) are replicated to `pond`. Sanoid snapshots all of `tank/media` recursively regardless of what gets replicated — datasets like `downloads`, `movies`, `shows`, `music` are snapshotted locally but intentionally **not** mirrored offsite (presumed re-acquirable / lower priority for USB backup space).

---

## Secondary Pool (USB SSD)

Pool name: `pond`
Mountpoint: `/pond`
Disk: Samsung PSSD T7 (2TB), `ID_SERIAL` matching `Samsung_PSSD_T7_S7MNNS0Y600957F*`

Created with:

- ashift=12
- compression=lz4 (pool default)
- atime=off
- xattr=sa
- acltype=posixacl
- autoexpand=on

Datasets currently present on `pond`:

```
pond/backups
pond/backups/apps/{grist,homarr,keycloak,lidarr,mathesar,memos,n8n,prowlarr,radarr,sabnzbd,sonarr,stash,vaultwarden}
pond/media/docs
pond/media/immich
pond/media/videos
```

`readonly=on` is set on `pond/backups`:

```
zfs set readonly=on pond/backups
```

Note: the `readonly` property does not prevent replication of new/nested datasets (e.g. `tank/backups/apps/newapp`) — `zfs receive` temporarily overrides `readonly` internally during replication. The flag only guards against accidental manual writes to the backup pool.

Purpose:

- Passive replication target for selected critical datasets
- No independent snapshot policy — `pond` does not run Sanoid
- Mirrors retention of source for replicated datasets only

---

# 2. Snapshot Management

Snapshots are managed on `tank` only, via Sanoid (`sanoid.timer`). `pond` does not run Sanoid — its snapshots exist solely as a byproduct of `syncoid` replication and are pruned in step with the source when Sanoid prunes `tank`.

---

# 3. Replication

Replication is performed using Syncoid, driven by a wrapper script (not inline in the unit file, as earlier documentation stated).

## Current replication set

| Source              | Target              | Recursive?          |
| ------------------- | ------------------- | ------------------- |
| `tank/backups`      | `pond/backups`      | yes (`--recursive`) |
| `tank/media/docs`   | `pond/media/docs`   | no                  |
| `tank/media/immich` | `pond/media/immich` | no                  |
| `tank/media/videos` | `pond/media/videos` | no                  |

**Not replicated:** `tank/media/audiobooks`, `downloads`, `movies`, `music`, `share`, `shows` — snapshotted locally on `tank` via Sanoid, but no offsite/USB copy exists for these.

## 3.1 Systemd Service

File: `/etc/systemd/system/syncoid.service`

```ini
[Unit]
Description=Replicate ZFS snapshots
Documentation=man:syncoid(8)
Requires=zfs.target
After=zfs.target

[Service]
Type=oneshot
Environment=TZ=UTC
ExecStart=/usr/local/bin/syncoid-replicate.sh
```

Wrapper script: `/usr/local/bin/syncoid-replicate.sh`

```bash
#!/bin/bash
set -e

# Check if pond is available
if ! zpool list pond >/dev/null 2>&1; then
    echo "pond pool not available, skipping replication"
    exit 0
fi

/usr/sbin/syncoid --no-sync-snap --compress=lz4 tank/backups pond/backups --recursive
/usr/sbin/syncoid --no-sync-snap --compress=lz4 tank/media/docs pond/media/docs
/usr/sbin/syncoid --no-sync-snap --compress=lz4 tank/media/immich pond/media/immich
/usr/sbin/syncoid --no-sync-snap --compress=lz4 tank/media/videos pond/media/videos
zfs mount -a
```

Behavior:

- Runs once per trigger
- Checks whether `pond` pool exists before executing any of the four replication steps
- **Skips ALL FOUR replication jobs silently** if `pond` is not imported — no error, no alert, no log beyond a single "not available" line (see TODO at top of doc)
- Does not delay or block system boot
- Recursively replicates newly created datasets under `tank/backups` automatically (e.g. `tank/backups/apps/newapp`); the three `media/*` jobs are per-dataset only, not recursive

## 3.2 Systemd Timer

File: `/etc/systemd/system/syncoid.timer`

```ini
[Unit]
Description=Daily Syncoid Timer

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Behavior:

- Runs daily at 06:00
- `Persistent=true` — if the system was powered off, the run fires immediately after next boot
- Independent from Sanoid's schedule
- Fully managed via systemd (no cron jobs)

> Note: unit naming should be double-checked for consistency — confirm actual installed unit name via `systemctl list-units | grep syncoid` (earlier notes referenced `syncoid-backups.timer` vs `syncoid.timer`).

---

# 4. Retention Strategy

Strategy: mirror retention, for replicated datasets only.

- Snapshot retention is controlled exclusively by Sanoid on `tank`
- When snapshots are pruned on `tank`, the next successful Syncoid run removes the corresponding ones from `pond`
- `pond` is a snapshot mirror for its four datasets, not an independent backup lifecycle
- **Risk:** if `pond` is unavailable for longer than the retention window of the _oldest_-retained snapshot type (currently `monthly=3`, i.e. up to ~90 days), the common snapshot needed for incremental replication can be pruned from `tank` before ever reaching `pond`, forcing a full resend. This nearly happened during the 2026-05-16 → 2026-07-25 gap (see Section 5.1) — the last shared snapshot was a `monthly` due to expire around September.

---

# 5. Failure Scenarios

## USB Unplugged

- System boots normally
- `pond` pool not imported
- `syncoid-replicate.sh` safely skips all replication (silently — see TODO)
- No boot delays

## NAS Reboot (USB connected)

- **Currently NOT reliable** — `pond` has been observed not to auto-import even with the disk connected at boot time. This is the primary open issue (see TODO at top of document).
- Sanoid continues via its own systemd timer regardless (snapshotting on `tank` is unaffected)
- Syncoid timer still fires on schedule, but its guard clause causes it to skip if `pond` didn't import

## Replace USB With Larger Disk

Because `autoexpand=on` is set, the pool should expand automatically after disk replacement — not re-tested since original setup.

## 5.1 Incident: 2026-05-16 to 2026-07-25 replication gap

`pond` was found un-imported despite the USB disk being connected (confirmed via `lsblk` showing `sdd` present, `zpool status pond` failing, `zpool import` showing the pool importable and healthy). Root cause: no auto-import mechanism exists for `pond` on this system — neither at boot nor on hotplug.

Impact: all four replication jobs (`backups`, `media/docs`, `media/immich`, `media/videos`) silently stopped updating `pond` from 2026-05-16 onward, undetected until manually checked on 2026-07-25 (~70 days).

Resolution: `pond` manually re-imported (`zpool import pond`); all four datasets manually caught up via their respective `syncoid` commands; verified fully in sync (no snapshots on `tank` missing from `pond`) as of 2026-07-25.

Follow-up: see TODO at top of document for the permanent fix (auto-import + alerting on skip).

---

# 6. Disaster Recovery (High Level)

If primary `tank` data is lost:

1. Import `pond`:
   ```
   zpool import pond
   ```
2. Identify desired snapshot
3. Restore using `zfs send | zfs receive` or clone snapshot

Full restore procedure should be tested periodically — not yet done as of this revision.

---

# 7. Operational Notes

- No entries added to `/etc/fstab`
- Snapshot automation via Sanoid systemd timer; replication automation via `syncoid.timer` + `syncoid.service` + wrapper script
- No cron jobs used
- Replication depends on snapshot existence
- `lz4` userspace tool installed for replication stream compression

---

# 8. Adding a New Dataset

## 8.1 Add a new dataset to `tank`

1. Create the dataset under the appropriate parent:
   ```bash
   zfs create tank/backups/apps/newapp
   # or, for media:
   zfs create tank/media/newthing
   ```
2. Confirm it inherits Sanoid snapshotting:
   - Datasets under `tank/backups` and `tank/media` are covered automatically, since both parents are configured with `recursive = yes` in `/etc/sanoid/sanoid.conf` (see Section 1). No config change needed for a plain nested dataset.
   - Verify on the next Sanoid run (or force one) that snapshots appear:
     ```bash
     systemctl start sanoid.service   # or wait for sanoid.timer
     zfs list -t snapshot tank/backups/apps/newapp   # adjust path
     ```
   - If the new dataset needs _different_ retention than its parent template, add an explicit `[tank/path/to/dataset]` section with its own `use_template` in `sanoid.conf` — otherwise it silently inherits the parent template, which is usually what you want.

## 8.2 Include it in replication to `pond`

Only datasets explicitly listed in `/usr/local/bin/syncoid-replicate.sh` get replicated — nothing is automatic here, unlike Sanoid's recursive snapshotting.

1. **If the new dataset is under `tank/backups`:** nothing to do — the existing `--recursive` syncoid call already covers it:
   ```bash
   /usr/sbin/syncoid --no-sync-snap --compress=lz4 tank/backups pond/backups --recursive
   ```
2. **If the new dataset is under `tank/media` (or anywhere else):** it must be added as its own explicit line, since the `media/*` jobs are per-dataset, not recursive. Edit `/usr/local/bin/syncoid-replicate.sh` and add:

   ```bash
   /usr/sbin/syncoid --no-sync-snap --compress=lz4 tank/media/newthing pond/media/newthing
   ```

   Add this line in the same style/place as the existing `docs`/`immich`/`videos` lines.

   > **Note on `--recursive`:** this flag is only needed when the source dataset has its own **child datasets** nested inside it (e.g. `tank/backups/apps/grist` is a separate ZFS dataset nested under `tank/backups`, not just a subdirectory). Without `--recursive`, syncoid still copies everything inside the dataset — all regular files and subdirectories are included in a single `zfs send`; nothing is skipped just because the flag is absent. The flag only controls whether syncoid also walks down into further datasets underneath.
   >
   > Practical implication: `tank/media/docs`, `immich`, and `videos` currently have no child datasets, so the plain (non-recursive) form above is correct and complete. But if a child dataset is ever created under one of these later (e.g. `zfs create tank/media/docs/scans`), that new child dataset will **not** be picked up by the existing line — it would need either `--recursive` added to that line, or its own separate line, or it will silently fail to replicate at all (same class of silent gap as the pond auto-import issue in Section 5.1). Worth checking `zfs list -r tank/media/<dataset>` periodically to confirm no new child datasets have appeared unnoticed.

3. Run the script manually once to do the initial full replication and confirm it works before waiting for the next scheduled run:
   ```bash
   /usr/local/bin/syncoid-replicate.sh
   ```
4. Verify the new dataset now exists on `pond` with a matching latest snapshot:
   ```bash
   zfs list -t snapshot -o name,creation -s creation tank/media/newthing | tail -3
   zfs list -t snapshot -o name,creation -s creation pond/media/newthing | tail -3
   ```
5. Update this document's replication table in Section 3 ("Current replication set") and the dataset lists in Section 1 to keep them accurate — this doc has already drifted from reality once (see Section 5.1); keeping it in sync going forward avoids repeating that.

---

# 9. Future Improvements / Open TODOs

- [ ] **High priority:** fix `pond` auto-import on boot and on hotplug (see TODO at top of document)
- [ ] Add alerting/notification when `syncoid-replicate.sh` skips due to `pond` being unavailable, so a recurrence of Section 5.1 is caught within hours/days, not months
- [ ] Verification/monitoring: periodic automated check comparing latest snapshot on `tank` vs `pond` for each replicated dataset, alerting on drift
- [ ] Decide whether any of the currently-unreplicated `tank/media` datasets (`audiobooks`, `downloads`, `movies`, `music`, `share`, `shows`) should be added to the replication set, or explicitly document them as intentionally excluded
- [ ] Offsite replication (remote Syncoid over SSH)
- [ ] Infrastructure-as-code automation (Ansible) for this whole setup
- [ ] Periodic restore testing procedure documentation

---

# 10. Summary

Primary snapshots: `tank` (Sanoid)
Replication: `tank/backups` (recursive) + `tank/media/{docs,immich,videos}` → `pond` (Syncoid via systemd, wrapper script)
Retention: mirrored, for replicated datasets only
USB behavior: safe if disconnected; **NOT currently reliable for auto-import when connected** (open TODO)
Automation: systemd timers

This setup provides a backup structure of:

1. Live data (primary storage on `tank`)
2. Snapshot-managed ZFS dataset (`tank/backups`, `tank/media/*`)
3. Selectively replicated ZFS USB pool (`pond`) — critical/irreplaceable data only

Date documented: 2026-02
Last revised: 2026-07-25 (post-incident update, reflects actual script contents and current replication scope; added auto-import TODO)
