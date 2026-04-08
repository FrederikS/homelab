# Repository Guidelines for AI Agents

This document provides essential context and instructions for AI agents working on this homelab Kubernetes cluster repository.

## Project Overview

This is a GitOps-managed homelab Kubernetes cluster using:

- **k3s**: Lightweight Kubernetes distribution
- **Flux CD**: GitOps continuous delivery tool
- **Ansible**: Node preparation and cluster installation
- **SOPS + PGP**: Secrets encryption

The repository is the single source of truth.
Changes committed here are automatically applied to the cluster by Flux.

## Repository Structure

```text
.
├── ansible/              # Ansible playbooks and inventory for node/cluster management
│   ├── inventory/homelab/ # Host definitions and variables (includes SOPS-encrypted secrets)
│   └── roles/           # Ansible roles
├── kubernetes/          # Kubernetes manifests and Flux configuration
│   ├── apps/            # Applications organized by cluster and namespace
│   │   └── <cluster>/<namespace>/<app>/
│   ├── archive/        # Archived apps, contains permanent or temporary disabled apps
│   ├── clusters/       # Flux cluster configuration and app definitions
│   ├── repositories/   # Common flux repositories
│   ├── config/<cluster> # Cluster configuration like common secrets and vars
│   └── components/     # Reusable components (e.g., backup)
├── scripts/            # Utility scripts (bash with shellcheck, python with uv/ruff)
└── docs/              # Human-readable documentation
```

## Nix Development Environment

This repository uses Nix flakes to provide a consistent development environment with all required tools (kubectl, flux, helm, sops, etc.).

### Running Commands with Nix

Use the `nix develop` wrapper to run commands with the correct tools and kubeconfig:

```bash
nix develop -c env <command>
```

If running with `nix develop` fails, add `--extra-experimental-features` flags:

```bash
nix --extra-experimental-features 'nix-command flakes' develop -c env <command>
```

Examples:

```bash
# kubectl commands
nix develop -c env kubectl get pods -n network

# flux commands
nix develop -c env flux get hr -A
```

## Kubectl and Flux Operations

- **Use nix develop wrapper**: All kubectl/flux commands should use the nix develop pattern:

  ```bash
  nix develop -c env <command>
  ```

### Security Rules

**CRITICAL: Secret Access is Forbidden**

NEVER access the contents of Kubernetes secrets. This is enforced at the command level:

- ✅ `kubectl get secret[s]` (without `-o` or `--output`) - lists secret names only
- ❌ `kubectl get secret[s] -o yaml/json/jsonpath` - FORBIDDEN
- ❌ `kubectl get externalsecret[s]` - FORBIDDEN
- ❌ `kubectl get secretstore[s]` - FORBIDDEN
- ❌ `kubectl get clustersecretstore[s]` - FORBIDDEN
- ❌ Any command using `-o yaml`, `-o json`, `--output`, `-ojson`, `-oyaml` on secrets

**CRITICAL: Cluster State Changes Require Approval**

NEVER mutate cluster state without explicit human approval. "Mutate" includes:

- `kubectl apply`, `kubectl delete`, `kubectl edit`, `kubectl patch`
- `kubectl rollout restart`, `kubectl scale`, `kubectl cordon/drain/uncordon`
- `helm install/upgrade/uninstall`
- `flux reconcile`, `flux suspend`, `flux resume`
- `ansible-playbook` (any playbook that touches nodes/cluster)

If a request appears to require mutating actions, stop and ask the user to confirm the exact command(s).

**Allowed kubectl operations** (read-only):

```
kubectl get, kubectl describe, kubectl logs, kubectl top, kubectl events
kubectl api-resources, kubectl api-versions, kubectl cluster-info
kubectl version, kubectl explain
```

**Allowed flux operations** (read-only):

```
flux get, flux logs, flux check, flux tree, flux trace
```

### Command Syntax

- Informational queries (get, describe, logs, events, etc.) are permitted; avoid destructive actions unless explicitly requested.

- Command ordering follows the prefix-based ruleset: `<command> <verb> <type> [output flags] [other flags] -n <namespace> [name]`.
  Keep the resource type immediately after the verb and put namespace flags last so output-format flags (`-o/--output`) stay adjacent to the type for secret-safety controls.

- Examples with ordering:

  ```bash
  nix develop -c env kubectl get pods -n <namespace>
  nix develop -c env kubectl get pod <name> -n <namespace>
  nix develop -c env kubectl logs -n <namespace> <pod>
  nix develop -c env flux get hr -n <namespace>
  ```

- Keep commands scoped and explicit; do not rely on default namespaces or contexts when fetching cluster state.

## Networking Architecture

Understanding the networking stack is critical for configuring ingress correctly.

### Network Components

#### kube-vip

- Provides high-availability VIP for the control plane
- Manages the cluster API endpoint

#### k8s-gateway

- Provides internal DNS resolution for cluster services
- Resolves `*.domain.com` queries from internal network
- Requires split DNS configuration on home DNS server (e.g., AdGuard Home)

#### Ingress NGINX (Internal)

- Ingress class: `internal`
- For services that should only be accessible within the home network
- Examples: Hubble UI, internal dashboards, home automation
- Does NOT route through Cloudflare

#### Ingress NGINX (External)

- Ingress class: `external`
- For services that need to be accessible from the internet
- Routes through Cloudflare Tunnel for security
- Requires external-dns annotation for DNS record creation

#### Cloudflare Tunnel

- Secure tunnel from Cloudflare edge to the cluster
- No exposed ports on home network
- Provides WAF and DDoS protection

#### external-dns

- Automatically manages DNS records in Cloudflare
- Reads ingress annotations to create/update DNS entries
- Watches for `external` ingress class resources

#### cert-manager

- Provides TLS certificates via Let's Encrypt
- Supports both staging and production environments
- Uses Cloudflare DNS challenge for wildcard certificates

### Choosing the Right Ingress Pattern

For internal-only services:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-internal-app
spec:
  parentRefs:
    - name: internal
      namespace: network
      sectionName: https
```

For publicly accessible services:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-public-app
  annotations:
    external-dns.alpha.kubernetes.io/target: external.<domain>
spec:
  parentRefs:
    - name: external
      namespace: network
      sectionName: https
```

## Application Development Workflow

### BEFORE Modifying Any Existing App

1. **Read the app's README.md**: `kubernetes/apps/<namespace>/<app>/README.md`
2. **Read the app's upstream documentation**: Helm chart docs, official docs
3. **Understand dependencies**: Check what other apps this depends on
4. **Review current configuration**: Look at HelmRelease values and customizations

### WHEN Adding a New App

Required structure:

```text
kubernetes/apps/<cluster>/<namespace>/<app>/
├── README.md                    # MANDATORY - Document the app
├── ks.yaml                      # Flux Kustomization for this app
└── app/
    ├── kustomization.yaml
    ├── helmrelease.yaml         # Or raw manifests
    └── *.sops.yaml             # Encrypted secrets if needed
```

README.md must include:

- Purpose and description of the app
- Configuration details and important settings
- Dependencies (other apps, infrastructure requirements)
- Known issues or gotchas
- Links to upstream documentation

#### Steps

1. Research the application and read its official documentation
2. Create the directory structure
3. Write the README.md first
4. **Use bjw-s app-template**: Always prefer the [bjw-s app-template](https://github.com/bjw-s/helm-charts) (`ghcr.io/bjw-s-labs/helm/app-template`) over dedicated Helm chart repositories when available. This provides a consistent deployment pattern across apps. Reference existing apps like `it-tools`, `memos`, or `ollama` for the structure.
5. Create HelmRelease using the app-template pattern
6. Security is very important, if possible containers should run as non-root and should not have any extended privileges:

   ```yaml
   # Pod-level (chart-specific key varies: podSecurityContext, securityContext, pod.securityContext)
   podSecurityContext:
     runAsNonRoot: true
     seccompProfile:
       type: RuntimeDefault

   # Container-level (every container)
   securityContext:
     allowPrivilegeEscalation: false
     capabilities:
       drop: ["ALL"]
     readOnlyRootFilesystem: true
     runAsNonRoot: true
     seccompProfile:
       type: RuntimeDefault
   ```

7. Add to `kubernetes/clusters/prod/apps.yaml` if needed
8. Test with: `flux get hr -n <namespace> <app>`

### WHEN Modifying Existing Apps

1. Always read and update the README.md if configuration changes
2. Test changes don't break dependencies
3. Verify Flux reconciliation after changes
4. Document any new gotchas discovered

## Secret Management (CRITICAL)

**SECURITY BOUNDARY**: All secrets must be encrypted with SOPS. DO NOT read and memorize those.

### Rules

- ✅ All `*.sops.yaml` files MUST be encrypted with SOPS
- ❌ NEVER commit unencrypted secrets
- ✅ ALWAYS verify encryption before `git push`
- ✅ Use PGP encryption (not age)

### Environment Variables

```bash
# <cluster>.env e.g. for prod cluster:
dotenv .prod.env
```

### Commands

Encrypt a new secret:

```bash
sops --encrypt --in-place kubernetes/apps/namespace/app/secret.sops.yaml
```

Edit an encrypted secret:

```bash
sops kubernetes/apps/namespace/app/secret.sops.yaml
# Opens in $EDITOR, auto-encrypts on save
```

Decrypt for reading (don't save):

```bash
sops --decrypt kubernetes/apps/namespace/app/secret.sops.yaml
```

Verify a file is encrypted:

```bash
grep -q "sops:" kubernetes/apps/namespace/app/secret.sops.yaml && echo "Encrypted" || echo "UNENCRYPTED!"
```

### Creating Secrets

All Kubernetes secrets should use the SOPS encrypted format:

```yaml
# secret.sops.yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
stringData:
  key: value
```

Then encrypt: `sops --encrypt --in-place secret.sops.yaml`

## Testing & Validation

### Flux Health Checks

Check all Flux sources:

```bash
flux get sources git -A
flux get sources oci -A
```

Check Kustomizations:

```bash
flux get ks -A
```

Check Helm Releases:

```bash
flux get hr -A
```

Force reconciliation:

```bash
flux reconcile ks <name> --with-source
flux reconcile hr -n <namespace> <name>
```

### Kubernetes Debugging

Check pod status:

```bash
kubectl get pods -n <namespace>
kubectl get pods -A  # All namespaces
```

Describe resources:

```bash
kubectl describe pod -n <namespace> <pod-name>
kubectl describe helmrelease -n <namespace> <name>
```

View logs:

```bash
kubectl logs -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> -f  # Follow
```

Check events:

```bash
kubectl get events -n <namespace> --sort-by='.metadata.creationTimestamp'
```

Pre-commit hooks:

The repository has pre-commit hooks.

```bash
pre-commit run --all-files
```

## File Naming Conventions

- **SOPS encrypted files**: `*.sops.yaml` (templates without secret values are `*.sops.yaml.tmpl`)
- **Kustomization files**: `kustomization.yaml` or `ks.yaml`
- **HelmRelease files**: `helmrelease.yaml` or `<app>-helmrelease.yaml`
- **App README**: Always `README.md` (not readme.md or README.MD)
- **ConfigMaps/Secrets**: Descriptive names like `app-config.yaml`, `app-secret.sops.yaml`
- **PVCs**: If an app uses a single PVC, name it exactly as the app (e.g., `linkding` not `linkding-data`)

## Commit Message Convention

All commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification.

### Format

```text
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s)]
```

### Rules

**Type and Description:**

- Allowed types: `feat`, `fix`, `build`, `chore`, `ci`, `docs`, `style`, `refactor`, `test`, `revert`
- Use imperative, present tense (e.g., "add feature" not "added feature")
- No trailing period on the description
- Prefer lowercase unless referencing a proper noun
- Keep the description concise and specific

**Scope:**

- Use a short, specific scope that identifies the area of change
- Examples: `api`, `ui`, `deps`, `ci`, `docs`, `flux`, `ansible`, `networking`
- Scope is optional but recommended for clarity

**Breaking Changes:**

- Mark breaking changes with `!` after the type/scope: `feat(api)!: change authentication method`
- Include a `BREAKING CHANGE:` footer describing the impact and migration path

**Body:**

- Explain what and why, not how
- Use bullet points for lists
- Avoid repeating the subject line
- Separate from subject with a blank line

**Footers:**

- Use `BREAKING CHANGE:` footer for breaking changes
- Coding assistants MUST indicate their assistance via a co-authored-by message: `Co-authored-by: <agent name><email>`
- Reference issues/PRs: `Closes #123`, `Refs #456`, `Fixes #789`

### Type Guidance

- `feat`: New user-facing behavior or capability
- `fix`: Bug fix that affects users
- `docs`: Documentation only changes
- `style`: Formatting changes that don't affect code meaning (whitespace, formatting, etc.)
- `refactor`: Code changes that neither fix bugs nor add features
- `test`: Adding or updating tests only
- `build`: Changes to build system, dependencies, or tooling (e.g., npm, ansible roles)
- `ci`: CI/CD configuration changes (e.g., GitHub Actions, Flux)
- `chore`: Routine tasks, maintenance, or other changes that don't modify src or test files
- `revert`: Reverts a previous commit

### Examples

```text
feat(networking): add external ingress for blog service

Configures HTTPRoute with external gateway and Cloudflare DNS annotation
to make the blog publicly accessible.

Closes #42
```

```text
fix(cert-manager): resolve certificate renewal failures

The ClusterIssuer was using an expired API token. Updated the secret
with a new token and verified certificate issuance.

Fixes #128
```

```text
chore(deps): update flux to v2.3.0

Updated Flux components to latest stable release for security patches
and performance improvements.
```

```text
feat(storage)!: migrate from openebs-hostpath to rook-ceph

BREAKING CHANGE: All PVCs must be migrated manually. openebs-hostpath storage
class is deprecated and will be removed in the next release.

Migration guide: docs/storage-migration.md

Refs #201
```

## Important Gotchas

### Security

1. **Always verify SOPS files are encrypted before committing**

   ```bash
   # Check all SOPS files are encrypted
   find . -name "*.sops.yaml" -exec grep -L "sops:" {} \;
   # Should return nothing if all are encrypted
   ```

2. **Never commit any encryption key file for age or pgp**

3. **Secrets in Ansible inventory** are also SOPS-encrypted (e.g., `host_vars/*.sops.yaml`, `group_vars/**/*.sops.yaml`)

### DNS & Networking

1. **Split DNS is required** for k8s-gateway to work

- Home DNS server must forward `*.domain.com` to k8s-gateway IP
- Without this, internal services won't resolve

2. **Certificate staging vs production**

- Cluster starts with Let's Encrypt staging certificates
- Switch to production once stable to avoid rate limits
- Staging certs will show browser warnings

3. **Cloudflare tunnel** must be configured for external ingress to work

- Check `kubernetes/apps/<cluster>/networking/cloudflare-tunnel/` for configuration

### Flux & GitOps

1. **Changes may take up to 30 minutes** to reconcile (default interval)

- Force reconciliation for immediate updates

### Cluster Operations

1. **Don't assume cluster is accessible** - verify connection before running kubectl commands:

   ```bash
   kubectl cluster-info
   ```

2. **Node operations** require Ansible and SSH access to nodes

3. **Rook-Ceph operations** need special care - contact the cluster owner before making any changes to Rook-Ceph resources.

## Ansible Operations

### Inventory Structure

```text
ansible/inventory/homelab/
├── hosts.ini              # Main inventory
├── group_vars/            # Variables for groups
└── host_vars/             # Per-host variables
```

### Running Playbooks

Check inventory:

```bash
ansible-inventory -i ansible/inventory --list
```

Run a playbook:

```bash
ansible-playbook <playbook>.yaml
```

### Common Playbooks

- `site.yml` - Main playbook to bootstrap machines, install and setup k3s on nodes
- `reset.yml` - Uninstall packages set up by site.yml - never run automatically - needs HUMAN APPROVAL

## References

- [README.md](./README.md) - Comprehensive setup and user documentation
- [Ansible Documentation](https://docs.ansible.com/) - Ansible official docs
- [Flux Documentation](https://fluxcd.io/flux/) - Flux CD official docs
- [k3s Documentation](https://docs.k3s.io/) - k3s official docs
- [SOPS Documentation](https://github.com/getsops/sops) - SOPS usage and configuration

## Memory

- Always remember I am using FluxCD and kustomizations
- Storage: Rook Ceph for fast storage, NFS ZFS for bulk/media storage
- PostgreSQL is the preferred database; use it for new apps when possible
- Never use kubectl apply since I am using FluxCD
- Prefer OCI repos over Helm repos for HelmReleases
- **Prefer bjw-s app-template** (`ghcr.io/bjw-s-labs/helm/app-template`) over dedicated Helm chart repositories
- Never mention a domain in a file - always use variable substitution
- `domain.com` is used as placeholder for the actual secret custom tld domain

---

Remember: This repository manages real infrastructure.
Always test changes carefully, verify SOPS encryption, and understand the impact before committing.
