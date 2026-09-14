# Shelfmark

Self-hosted web interface for searching and requesting audiobooks across multiple sources.

## Purpose

Provides a search UI for audiobook discovery and download. Works alongside audiobookshelf — shelfmark handles searching and downloading, audiobookshelf handles playback.

## Configuration

- **Port**: 8084 (internal ingress)
- **Media**: NFS mount at `/tank/media/audiobooks` → `/media` (writable)
- **Ingress**: Internal only (`className: internal`), accessible at `shelfmark.${SECRET_DOMAIN}`
- **Image**: shelfmark-lite (no Chromium, lower memory)

## Dependencies

- Rook-Ceph cluster (for PVC storage)
- NFS server (for audiobook media storage)
- Audiobookshelf (for playback, linked via UI button)

## Upstream

- [GitHub](https://github.com/calibrain/shelfmark)
- [Documentation](https://github.com/calibrain/shelfmark/blob/main/docs/environment-variables.md)
