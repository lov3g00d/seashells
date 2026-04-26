# Cloud Auth Shell

Multi-cloud & Kubernetes profile manager. Discovers existing profiles from native CLI configs automatically.

## Quick Start

```bash
# With direnv (recommended — preserves your shell, autosuggestions, etc.)
echo 'use flake "github:lov3g00d/seashells?dir=shells/cloud-auth"' > .envrc
direnv allow

# Or directly
nix develop 'github:lov3g00d/seashells?dir=shells/cloud-auth'
```

Then:

```bash
cloud              # fzf picker — select any profile
cloud ls           # list all discovered profiles
cloud help         # full help
```

## Commands

```bash
# Select (fzf)
cloud                             # pick any profile

# Activate
eval "$(cloud use aries)"        # activate by name
eval "$(cloud use aws:aries)"    # activate with explicit provider

# Info
cloud ls              # list all profiles
cloud current         # show active
cloud status          # check auth validity
cloud refresh         # re-auth active sessions
```

## How It Works

Reads directly from native CLI config files — no separate config to maintain:

| Provider | Source |
|----------|--------|
| AWS | `~/.aws/config` (`[profile ...]` sections) |
| GCP | `~/.config/gcloud/configurations/config_*` |
| Azure | `~/.azure/azureProfile.json` |
| K8s | `kubectl config get-contexts` |

Configure profiles using native CLIs as usual (`aws configure sso`, `gcloud init`, `az login`), and `cloud` discovers them automatically.

## Tools Included

- AWS: `awscli2`
- GCP: `google-cloud-sdk`
- Azure: `azure-cli`
- IaC: `terraform`
- K8s: `kubectl`, `kubectx`, `helm`, `k9s`, `stern`
- Utils: `jq`, `fzf`
