# ZFS Backup Architecture Documentation

## Overview

This document describes the backup architecture implemented on the NAS (Proxmox bare metal) using ZFS, Sanoid, and Syncoid.

Architecture goal:

- Snapshot-based backups on primary storage
- Replication of backup datasets to external USB SSD
- Clean separation of snapshot management and replication
- Safe operation even if USB disk is disconnected

---

# 1. Storage Layout

## Primary Pool

Pool name: `tank`
Mountpoint: `/tank`

Relevant dataset:

```
tank/backups
```

Snapshots are managed by Sanoid configured in `/etc/sanoid/sanoid.conf`

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

---

## Secondary Pool (USB SSD)

Pool name: `pond`
Mountpoint: `/pond`
Disk: Samsung PSSD T7 (2TB)

Created with:

- ashift=12
- compression=lz4 (pool default)
- atime=off
- xattr=sa
- acltype=posixacl

Dataset used for replication:

```
pond/backups
```

Additional settings:

```
zpool set autoexpand=on pond
zfs set readonly=on pond/backups

Note:
The readonly property does NOT prevent replication of new datasets such as `tank/backups/app/newapp`.
ZFS receive can write to a readonly dataset because it temporarily overrides the property internally during replication. The readonly flag only prevents accidental manual modifications on the backup pool.
```

Purpose:

- Passive replication target
- No independent snapshot policy
- Mirrors retention of source

---

# 2. Snapshot Management

Snapshots are managed on `tank` using Sanoid.

Sanoid runs via systemd timer:

```
sanoid.timer
```

Responsibilities:

- Create snapshots
- Prune snapshots according to retention policy

Retention policy is defined in `/etc/sanoid/sanoid.conf`.

Important: Only `tank` is snapshot-managed. `pond` does not run Sanoid.

---

# 3. Replication

Replication is performed using Syncoid.

Source:

```
tank/backups
```

Target:

```
pond/backups
```

Replication is recursive and mirrors snapshot structure.

---

## 3.1 Systemd Service

File:

```
/etc/systemd/system/syncoid.service
```

Contents:

```
[Unit]
Description=Replicate ZFS snapshots
Documentation=man:syncoid(8)
Requires=zfs.target
After=zfs.target

[Service]
Type=oneshot
Environment=TZ=UTC
ExecStart=/bin/bash -c 'zpool list pond >/dev/null 2>&1 && /usr/sbin/syncoid --recursive --no-sync-snap --compress=lz4 tank/backups pond/backups'
```

Behavior:

- Runs once per trigger
- Checks whether `pond` pool exists before executing
- Skips replication silently if USB disk is disconnected
- Does not delay or block system boot
- Recursively replicates newly created datasets automatically (e.g. `tank/backups/app/newapp`)

---

## 3.2 Systemd Timer

File:

```
/etc/systemd/system/syncoid.timer
```

Contents:

```
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
- If system was powered off, replication runs immediately after next boot
- Independent from Sanoid schedule
- Fully managed via systemd (no cron jobs)

Enabled with:

```
systemctl daemon-reload
systemctl enable syncoid-backups.timer
systemctl start syncoid-backups.timer
```

---

# 4. Retention Strategy

Strategy: Mirror retention.

Meaning:

- Snapshot retention is controlled exclusively by Sanoid on `tank`
- When snapshots are pruned on `tank`, Syncoid removes them from `pond`
- `pond` is a snapshot mirror, not an independent backup lifecycle

Advantages:

- Simplicity
- Predictability
- No drift between source and replica
- Reduced complexity

---

# 5. Failure Scenarios

## USB Unplugged

- System boots normally
- `pond` pool not imported
- Syncoid service safely skips replication
- No boot delays

## NAS Reboot

- ZFS pools auto-import
- Sanoid continues via systemd timer
- Syncoid timer continues automatically

## Replace USB With Larger Disk

Because `autoexpand=on` is set:

- Pool expands automatically after disk replacement
- No manual online expansion required

---

# 6. Disaster Recovery (High Level)

If primary `tank` data is lost:

1. Import `pond`:
   ```
   zpool import pond
   ```
2. Identify desired snapshot
3. Restore using `zfs send | zfs receive` or clone snapshot

Full restore procedure should be tested periodically.

---

# 7. Operational Notes

- No entries added to `/etc/fstab`
- All automation handled via systemd timers
- No cron jobs used
- Replication depends on snapshot existence
- `lz4` userspace tool installed for replication stream compression

---

# 8. Future Improvements (Optional)

- Offsite replication (remote Syncoid over SSH)
- Email alerting on replication failure
- Infrastructure-as-code automation (Ansible)
- Periodic restore testing procedure documentation

---

# Summary

Primary snapshots: `tank` (Sanoid)
Replication: `tank/backups` → `pond/backups` (Syncoid via systemd)
Retention: mirrored
USB behavior: safe if disconnected
Automation: systemd timers

This setup provides a three-layer backup structure:

1. Live data (Ceph / primary storage)
2. Snapshot-managed ZFS backup dataset
3. Replicated ZFS USB pool

Date documented: 2026-02
