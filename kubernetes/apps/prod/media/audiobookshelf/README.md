# Audiobookshelf

Audiobookshelf is a self-hosted audiobook and podcast server.

## Purpose

Provides a web-based interface for managing and streaming audiobooks and podcasts. Supports multiple users, progress tracking, and a range of client apps.

## Configuration

- **Port**: 80 (internal ingress)
- **Config data**: Stored on a 3Gi Rook-Ceph PVC
- **Media**: Audiobooks served from NFS at `/tank/media/audiobooks`
- **Ingress**: Internal only (`className: internal`), accessible at `audiobookshelf.${SECRET_DOMAIN}`

## Backups

Audiobookshelf has a built-in backup system that backs up the database and the
`metadata/` directory (covers, author/item metadata). Media files are **not**
included.

- **Location**: `BACKUP_PATH=/backups`, backed by NFS at
  `/tank/backups/apps/${APP}` (`${NAS_SERVER_IP}`)
- **Schedule / retention**: Configured in the web UI (Settings → Backups).
  Audiobookshelf has no environment variables for these settings; they are
  persisted in the server settings within the database. Because `BACKUP_PATH`
  is set via environment variable, the path field is read-only in the UI.
- **Restore**: Requires stopping the app. Use the "Restore" button in the
  Backups UI, or manually unzip the `.audiobookshelf` archive and replace
  `audiobookshelf.sqlite` plus the `metadata` `authors`/`items` folders.

## Dependencies

- Rook-Ceph cluster (for PVC storage)
- NFS server (for audiobook media and backups)

## Upstream

- [GitHub](https://github.com/advplyr/audiobookshelf)
- [Documentation](https://www.audiobookshelf.org/docs)
