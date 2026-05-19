# Profilarr

Profile validator for Radarr/Sonarr.

## Dependencies

- Rook Ceph cluster (for PVC)
- `${SECRET_DOMAIN}` variable defined

## Configuration

- Internal ingress only (accessible within the home network)
- Uses existing PVC for config storage
- Authentication disabled for local use

## Notes

- Image: `ghcr.io/dictionarry-hub/profilarr`
- Port: 6868
- Health endpoint: `/api/v1/health`

## Links

- [GitHub](https://github.com/dictionarry-hub/profilarr)
