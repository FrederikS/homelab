# Audiobookshelf

Audiobookshelf is a self-hosted audiobook and podcast server.

## Purpose

Provides a web-based interface for managing and streaming audiobooks and podcasts. Supports multiple users, progress tracking, and a range of client apps.

## Configuration

- **Port**: 80 (internal ingress)
- **Config data**: Stored on a 3Gi Rook-Ceph PVC
- **Media**: Audiobooks served from NFS at `/tank/media/audiobooks`
- **Ingress**: Internal only (`className: internal`), accessible at `audiobookshelf.${SECRET_DOMAIN}`

## Dependencies

- Rook-Ceph cluster (for PVC storage)
- NFS server (for audiobook media)

## Upstream

- [GitHub](https://github.com/advplyr/audiobookshelf)
- [Documentation](https://www.audiobookshelf.org/docs)
