# Homelab Kubernetes Cluster Overview

## Cluster Setup

- **Distribution:** k3s (single-stack IPv4, default configuration)
- **Provisioning:** Ansible
- **GitOps:** Flux with HelmRelease

---

## Networking

### CNI — Flannel (k3s default)

Flannel is the default CNI (Container Network Interface) for k3s. It handles pod networking, IP assignment, and routing between nodes. No advanced network policies — straightforward and stable for a homelab.

### IP Ranges (k3s defaults, nothing explicitly configured)

| Purpose            | CIDR           |
| ------------------ | -------------- |
| Pod network        | `10.42.0.0/16` |
| Service network    | `10.43.0.0/16` |
| kube-dns (CoreDNS) | `10.43.0.10`   |

> The kube-dns IP is always the 10th IP of the service CIDR — a k3s convention.

### IPv6

Single-stack IPv4 only. No IPv6 CIDRs were passed to k3s at install time, so pods and services only receive IPv4 addresses.

> Note: `cluster_cidr: 10.52.0.0/16` exists in `group_vars/all.yaml` but has no effect — it only feeds into the Cilium/Calico role which is not running. The cluster runs entirely on k3s defaults.

---

## VPN Setup (Gluetun + WireGuard)

The goal is to route specific pod traffic through a VPN without affecting the rest of the cluster. This is achieved at the **pod level** using Gluetun as a native sidecar container.

Gluetun supports many WireGuard providers (Mullvad, ProtonVPN, NordVPN, etc.) — only the provider-specific env vars change between them. See the [Gluetun provider docs](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers) for the exact variables required by your provider.

### How it works

All containers in a Kubernetes pod share the same **network namespace** — same IP, same network interfaces, same iptables rules. Gluetun exploits this by:

1. Bringing up a WireGuard tunnel interface inside the shared namespace
2. Setting iptables rules that route all pod traffic through the tunnel (kill switch)
3. The app container requires zero VPN awareness — the kernel handles routing transparently

### Native Sidecar Pattern (Kubernetes 1.29+)

Gluetun is defined under `initContainers` with `restartPolicy: Always`. This makes it a **native sidecar**:

- Starts before the app container (no VPN leak window)
- Runs for the lifetime of the pod
- Kubernetes restarts it if it crashes

```yaml
initContainers:
  gluetun:
    restartPolicy: Always  # makes this a native sidecar, not a regular initContainer
    ...
```

### Key Gluetun Configuration

**Generic (all providers):**

| Variable                      | Value                       | Purpose                               |
| ----------------------------- | --------------------------- | ------------------------------------- |
| `VPN_SERVICE_PROVIDER`        | e.g. `mullvad`, `protonvpn` | Your VPN provider                     |
| `VPN_TYPE`                    | `wireguard`                 | Protocol                              |
| `SERVER_COUNTRIES`            | e.g. `Netherlands`          | Server location preference            |
| `HEALTH_SERVER_ADDRESS`       | `:9999`                     | Health endpoint for Kubernetes probes |
| `HTTP_CONTROL_SERVER_ADDRESS` | `:8000`                     | Gluetun control API                   |
| `FIREWALL_INPUT_PORTS`        | e.g. `80,8000,9999`         | Ports allowed through the kill switch |
| `FIREWALL_OUTBOUND_SUBNETS`   | `10.42.0.0/16,10.43.0.0/16` | Cluster CIDRs that bypass the VPN     |

**Provider-specific (WireGuard):**

| Variable                | Purpose                                                       |
| ----------------------- | ------------------------------------------------------------- |
| `WIREGUARD_PRIVATE_KEY` | Your WireGuard private key — store in a Kubernetes Secret     |
| `WIREGUARD_ADDRESSES`   | IP assigned to your key by the provider (e.g. `10.68.x.x/32`) |

> Some providers (e.g. ProtonVPN) may require additional variables like `WIREGUARD_PUBLIC_KEY` or use a different auth mechanism. Always check the [Gluetun provider docs](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers) for your specific provider.

> `FIREWALL_OUTBOUND_SUBNETS` is only needed when the app also communicates with internal cluster services.

### Deployment Strategy

Must use `Recreate` instead of `RollingUpdate`:

```yaml
controllers:
  my-app:
    strategy: Recreate
```

**Why:** WireGuard uses IP rule table `51820`. With `RollingUpdate`, old and new pods overlap briefly — the new pod fails to add the rule because the old pod hasn't cleaned it up yet.

### postStart Lifecycle Hook

```yaml
lifecycle:
  postStart:
    exec:
      command:
        - /bin/sh
        - -c
        - "(ip rule del table 51820; ip -6 rule del table 51820) || true"
```

Cleans up leftover WireGuard IP rules from a previous abrupt shutdown (node crash, power event). The `|| true` prevents failure if rules don't exist on a clean start.

---

## Split DNS (required for internal + external traffic)

When an app needs to reach both the internet (via VPN) and internal cluster services, two additional things are needed:

### 1. FIREWALL_OUTBOUND_SUBNETS

Tells Gluetun to bypass the VPN tunnel for internal cluster CIDRs:

```yaml
FIREWALL_OUTBOUND_SUBNETS: 10.42.0.0/16,10.43.0.0/16
```

### 2. CoreDNS Sidecar (optional)

Gluetun has a built-in DNS resolver using DNS-over-TLS (DoT) via Cloudflare by default. This handles both internal cluster names (`*.cluster.local`) and external DNS transparently — so **a CoreDNS sidecar is not strictly required** for most setups.

You would add a CoreDNS sidecar when you need:

- **Explicit control** over which upstream DNS servers are used rather than relying on Gluetun's defaults
- **Custom forwarding rules** per domain
- **Additional CoreDNS features** like fine-grained caching, rewrite rules, or per-zone error logging
- Gluetun's built-in DNS is causing resolution issues for internal cluster names

When used, CoreDNS runs as a second native sidecar on `127.0.0.2`, handling split DNS:

```
cluster.local queries  →  10.43.0.10 (kube-dns, bypasses VPN)
everything else        →  public DNS of your choice (through VPN)
```

The Corefile is mounted into the CoreDNS sidecar via a ConfigMap:

```
.:53 {
    bind 127.0.0.2
    rewrite stop type AAAA A        # drop IPv6 queries — prevents IPv6 leaks
                                    # and avoids issues on this single-stack cluster
    errors
    health :8081 {                  # optional: health endpoint for Kubernetes probes
        lameduck 5s
    }
    log {
        class error
    }
    # Public DNS servers for external queries — goes through VPN so your
    # real IP is never exposed. Use any provider you prefer:
    #   Cloudflare: 1.1.1.1, 1.0.0.1
    #   Google:     8.8.8.8, 8.8.4.4
    #   OpenDNS:    208.67.222.222, 208.67.220.220
    #   Quad9:      9.9.9.9, 149.112.112.112 (blocks malicious domains)
    # Two servers is sufficient, extras are just for redundancy.
    forward . 1.1.1.1:53 1.0.0.1:53 {
        policy sequential           # try servers in order, only fall back on failure
        health_check 5s
    }
    reload
}

cluster.local:53 {
    bind 127.0.0.2
    rewrite stop type AAAA A
    errors
    log {
        class error
    }
    forward . 10.43.0.10            # kube-dns service IP (10th IP of service CIDR)
}
```

When using CoreDNS, Gluetun must be pointed at it instead of managing DNS itself:

```yaml
DOT: "off" # disable Gluetun's built-in DNS-over-TLS
DNS_ADDRESS: 127.0.0.2 # use the CoreDNS sidecar instead
DNS_KEEP_NAMESERVER: "off"
```

---

## Verification

To verify VPN is working, exec into any pod running Gluetun and check your public IP:

```bash
kubectl exec -it <pod> -c app -- curl -s https://ipinfo.io
```

This returns your current public IP and location. Cross-reference it with your VPN provider's server list to confirm traffic is routing through the VPN and not your real IP.

For Mullvad specifically, their API gives a more explicit confirmation:

```bash
kubectl exec -it <pod> -c app -- curl -s https://am.i.mullvad.net/json
```

```json
{
  "ip": "185.213.x.x",
  "mullvad_exit_ip": true,
  "country": "Netherlands"
}
```

`mullvad_exit_ip: true` explicitly confirms traffic is routing through Mullvad.
