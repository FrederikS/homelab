# ingress-nginx

Community ingress-nginx controller, deployed twice from the same Helm chart with different ingress classes:

| Release          | Ingress class               | Service      | Exposure                                                |
| ---------------- | --------------------------- | ------------ | ------------------------------------------------------- |
| `nginx-external` | `external` (default: false) | LoadBalancer | Origin for the Cloudflare Tunnel (`*.${SECRET_DOMAIN}`) |
| `nginx-internal` | `internal` (default: true)  | LoadBalancer | LAN only, resolved via `k8s-gateway`                    |

Both releases use the upstream chart from the `ingress-nginx` HelmRepository (`kubernetes/repositories/helm/ingress-nginx.yaml`) with version `*`, so they track the newest published chart. External additionally sets `default-ssl-certificate` to the cert-manager wildcard and enables external-dns via service annotations.

## NGINX2Root (CVE-2026-123007 and friends)

The community `ingress-nginx` project was archived in March 2026 and will not ship fixes, so the controller image (`v1.15.1`, bundling nginx 1.27.x) stays vulnerable to the [NGINX2Root](https://nginx2root.com/) flaws:

| CVE             | Relevance                                                        | Mitigated here?                                                                                                                                                                                                       |
| --------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CVE-2026-123007 | HTTP/2 memory corruption, unauthenticated RCE as the worker user | Yes, by `use-http2: "false"`                                                                                                                                                                                          |
| CVE-2026-123633 | HTTP/2 use-after-free when proxying to an upstream               | Yes, by `use-http2: "false"`                                                                                                                                                                                          |
| CVE-2026-123634 | DNS resolver use-after-free with a variable `proxy_pass`         | Not applicable: no request-dependent proxy targets. `auth-url` (tinyauth) adds a `resolver` but points at a fixed host. Do not add `configuration-snippet`/`server-snippet` that proxy to a variable such as `$host`. |
| CVE-2026-121810 | HTTP/3 (QUIC) use-after-free                                     | Not applicable: no QUIC listener, snippets are not used to add one                                                                                                                                                    |
| CVE-2026-113425 | Mail proxy use-after-free                                        | Not applicable                                                                                                                                                                                                        |

`use-http2: "false"` is a stopgap, not a fix: it disables HTTP/2 on every server block so the HTTP/2 bugs are unreachable. Native gRPC clients pointed at these controllers will stop working (browser and HTTP/1.1 traffic is unaffected). Because the setting changes the ConfigMap checksum, Flux rolls the controller pods on reconcile, which is required — a plain nginx reload leaves existing HTTP/2 connections open.

## TODO: migrate off this controller

The durable fix is a maintained ingress path. Options, roughly in order of effort:

1. A patched build of the controller image (Chainguard `ingress-nginx-controller-1.15:1.15.16-r0` or equivalent), overriding `controller.image` on both releases.
2. F5 NGINX Ingress Controller — note that 5.8.0 still shipped nginx 1.31.8, so only use a release that bundles 1.31.9/1.30.7 or newer.
3. Gateway API (Envoy Gateway or similar). This requires installing the Gateway API CRDs and rewriting every app's `Ingress` resource as an `HTTPRoute`, so it is a separate project.

Also worth doing regardless: block the Linux kernel SCTP module on the nodes (`install sctp /bin/false` in `/etc/modprobe.d/`), since the public nginx2root chain uses an SCTP flaw to escalate from the nginx worker to host root.

## Notes

- `allow-snippet-annotations` is enabled with `annotations-risk-level: Critical` on both controllers. Snippet annotations can re-introduce the HTTP/3 and resolver CVEs, so they should be kept to a minimum.
- Chart versions are not pinned (`version: "*"`), so a new upstream chart is picked up on the next HelmRepository refresh; that mechanism no longer produces releases for this project.
