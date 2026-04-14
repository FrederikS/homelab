# immich-drop

A tiny, zero-login web app for collecting photos/videos from anyone into your Immich server.

## Description

immich-drop allows admin users to create public invite links for uploading photos/videos directly to your Immich server. Invite links are public-by-URL and can be configured with passwords, album assignment, and expiry dates.

## Dependencies

- [immich](../immich/) - Required: Immich server must be running

## Configuration

### Required Secrets

| Key              | Description                                                                                                                |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `IMMICH_API_KEY` | Immich API key with asset.upload permissions (and album.create, album.read, albumAsset.create if album support is enabled) |

Note: `SESSION_SECRET` is auto-generated if not provided.

### Environment Variables

| Variable                     | Default                               | Description                                     |
| ---------------------------- | ------------------------------------- | ----------------------------------------------- |
| `IMMICH_BASE_URL`            | `https://immich.${SECRET_DOMAIN}/api` | Immich API base URL                             |
| `IMMICH_API_KEY`             | (secret)                              | API key for Immich                              |
| `PUBLIC_UPLOAD_PAGE_ENABLED` | `false`                               | Enable public upload page (disabled by default) |
| `IMMICH_ALBUM_NAME`          | (not set)                             | Album name to auto-assign uploads to            |
| `SESSION_SECRET`             | (secret)                              | Session encryption secret                       |
| `CHUNKED_UPLOADS_ENABLED`    | `false`                               | Enable chunked uploads for large files          |
| `CHUNK_SIZE_MB`              | `95`                                  | Chunk size in MB                                |

## Usage

**When needed:**

1. Temporarily enable password login on Immich server (Server Settings → Password Authentication)
2. Scale up the app:
   ```bash
   kubectl scale hr immich-drop -n default --replicas=1
   ```

**After use:**

1. Scale down the app:
   ```bash
   kubectl scale hr immich-drop -n default --replicas=0
   ```
2. Disable password login on Immich server

## Upstream Documentation

- GitHub: https://github.com/Nasogaa/immich-drop
- Docker Image: `ghcr.io/nasogaa/immich-drop`
