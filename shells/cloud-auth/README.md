# Cloud Auth Shell

Multi-cloud authentication shell with fzf interactive selector.

## Tools

- **AWS**: `awscli2`
- **GCP**: `google-cloud-sdk`
- **Azure**: `azure-cli`
- **IaC**: `terraform`
- **K8s**: `kubectl`, `kubectx`, `kubernetes-helm`, `k9s`, `stern`
- **Utils**: `jq`, `fzf`

## Usage

```bash
nix develop github:lov3g00d/seashells?dir=shells/cloud-auth
```

Or with direnv:

```bash
echo "use flake github:lov3g00d/seashells?dir=shells/cloud-auth" > .envrc
```

## Commands

```bash
cloud              # Interactive fzf selector
cloud aws [name]   # AWS profile auth
cloud gcp [name]   # GCP config auth
cloud azure [name] # Azure subscription auth
cloud status       # Auth status

add-aws <profile>  # Layer AWS auth
add-gcp <config>   # Layer GCP auth
cloud-refresh      # Re-authenticate all

ecr-login          # AWS ECR login
gcr-login          # Google Container Registry
gar-login          # Google Artifact Registry

kctx               # K8s context switch
kns                # K8s namespace switch
```
