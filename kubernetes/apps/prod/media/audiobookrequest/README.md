# AudioBookRequest

Audiobook request management/wishlist for Plex/Audiobookshelf/Jellyfin.

## Purpose

Provides a web interface for users to search for and request audiobooks via the Audible API. Integrates with Prowlarr for automatic downloading of requested books using existing indexer settings.

## Configuration

- **Port**: 8000 (internal ingress)
- **Config data**: Stored on a 1Gi Rook-Ceph PVC at `/config`
- **Ingress**: Internal only (`className: internal`), accessible at `abr.${SECRET_DOMAIN}`
- **Auto-download**: Enabled via Prowlarr API integration
- **Login**: Configurable in the web UI on first launch

## Dependencies

- Rook-Ceph cluster (for PVC storage)
- Prowlarr (for automatic downloads, uses shared `prowlarr-secret`)
- Audiobookshelf (optional, for library integration)

## Upstream

- [GitHub](https://github.com/markbeep/AudioBookRequest)
- [Wiki](https://github.com/markbeep/AudioBookRequest/wiki)
