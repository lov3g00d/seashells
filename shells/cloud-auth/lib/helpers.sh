# Cloud auth helper functions
# Sourced into all shells

# Colors
_c_red='\033[0;31m'
_c_green='\033[0;32m'
_c_yellow='\033[0;33m'
_c_blue='\033[0;34m'
_c_purple='\033[0;35m'
_c_cyan='\033[0;36m'
_c_reset='\033[0m'

# Show current cloud auth status
cloud-status() {
  echo -e "${_c_cyan}=== Cloud Auth Status ===${_c_reset}"
  echo ""

  # AWS Status
  if [[ -n "$AWS_PROFILE" ]]; then
    echo -e "${_c_yellow}AWS Profile:${_c_reset} $AWS_PROFILE"
    echo -e "${_c_yellow}AWS Region:${_c_reset} ${AWS_REGION:-not set}"
    echo -e "${_c_yellow}AWS Account:${_c_reset} ${AWS_ACCOUNT_ID:-not set}"
    if aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
      local identity=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --output json 2>/dev/null)
      local arn=$(echo "$identity" | jq -r '.Arn // "unknown"')
      echo -e "${_c_green}AWS Status:${_c_reset} Authenticated"
      echo -e "${_c_green}AWS Identity:${_c_reset} $arn"

      # Check SSO session expiry
      local cache_file=$(ls -t ~/.aws/sso/cache/*.json 2>/dev/null | head -1)
      if [[ -n "$cache_file" ]]; then
        local expiry=$(jq -r '.expiresAt // empty' "$cache_file" 2>/dev/null)
        if [[ -n "$expiry" ]]; then
          local expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
          local now_ts=$(date +%s)
          local remaining=$(( (expiry_ts - now_ts) / 60 ))
          if (( remaining > 0 )); then
            echo -e "${_c_green}AWS Session:${_c_reset} ${remaining}min remaining"
          else
            echo -e "${_c_red}AWS Session:${_c_reset} Expired"
          fi
        fi
      fi
    else
      echo -e "${_c_red}AWS Status:${_c_reset} Not authenticated"
    fi
    echo ""
  fi

  # GCP Status
  if [[ -n "$CLOUDSDK_ACTIVE_CONFIG_NAME" ]]; then
    echo -e "${_c_blue}GCP Config:${_c_reset} $CLOUDSDK_ACTIVE_CONFIG_NAME"
    echo -e "${_c_blue}GCP Project:${_c_reset} ${CLOUDSDK_CORE_PROJECT:-not set}"
    local account=$(gcloud config get-value account 2>/dev/null)
    if [[ -n "$account" ]] && gcloud auth print-access-token &>/dev/null 2>&1; then
      echo -e "${_c_green}GCP Status:${_c_reset} Authenticated"
      echo -e "${_c_green}GCP Account:${_c_reset} $account"
    else
      echo -e "${_c_red}GCP Status:${_c_reset} Not authenticated"
    fi
    echo ""
  fi

  # Kubernetes Status
  if command -v kubectl &>/dev/null; then
    local ctx=$(kubectl config current-context 2>/dev/null || echo "none")
    local ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "default")
    echo -e "${_c_purple}K8s Context:${_c_reset} $ctx"
    echo -e "${_c_purple}K8s Namespace:${_c_reset} $ns"
  fi
}

# Refresh all cloud credentials
cloud-refresh() {
  echo -e "${_c_cyan}Refreshing cloud credentials...${_c_reset}"

  if [[ -n "$AWS_PROFILE" ]]; then
    echo -e "${_c_yellow}Refreshing AWS SSO...${_c_reset}"
    aws sso login --profile "$AWS_PROFILE"
  fi

  if [[ -n "$CLOUDSDK_ACTIVE_CONFIG_NAME" ]]; then
    echo -e "${_c_blue}Refreshing GCP auth...${_c_reset}"
    local account=$(gcloud config get-value account 2>/dev/null)
    if [[ -n "$account" ]]; then
      gcloud auth login --account "$account" --update-adc
    fi
  fi

  echo -e "${_c_green}Done!${_c_reset}"
  cloud-status
}

# Show who you are across all clouds
cloud-whoami() {
  echo -e "${_c_cyan}=== Cloud Identities ===${_c_reset}"
  echo ""

  if [[ -n "$AWS_PROFILE" ]]; then
    echo -e "${_c_yellow}AWS:${_c_reset}"
    aws sts get-caller-identity --profile "$AWS_PROFILE" --output table 2>/dev/null || echo "  Not authenticated"
    echo ""
  fi

  if [[ -n "$CLOUDSDK_ACTIVE_CONFIG_NAME" ]]; then
    echo -e "${_c_blue}GCP:${_c_reset}"
    if gcloud auth print-access-token &>/dev/null 2>&1; then
      echo "  Account: $(gcloud config get-value account 2>/dev/null)"
      echo "  Project: $(gcloud config get-value project 2>/dev/null)"
    else
      echo "  Not authenticated"
    fi
    echo ""
  fi
}

# Quick switch AWS profile (within same SSO session)
aws-switch() {
  local profile="${1:-}"
  if [[ -z "$profile" ]]; then
    echo "Usage: aws-switch <profile>"
    echo "Available profiles:"
    grep -E '^\[profile ' ~/.aws/config 2>/dev/null | sed 's/\[profile /  /g; s/\]//g'
    return 1
  fi
  export AWS_PROFILE="$profile"
  echo -e "${_c_green}Switched to AWS profile: $profile${_c_reset}"
  cloud-status
}

# Quick switch GCP config
gcp-switch() {
  local config="${1:-}"
  if [[ -z "$config" ]]; then
    echo "Usage: gcp-switch <config>"
    echo "Available configs:"
    gcloud config configurations list --format='table(name,is_active,properties.core.account,properties.core.project)' 2>/dev/null
    return 1
  fi
  gcloud config configurations activate "$config"
  export CLOUDSDK_ACTIVE_CONFIG_NAME="$config"
  export CLOUDSDK_CORE_PROJECT=$(gcloud config get-value project 2>/dev/null)
  echo -e "${_c_green}Switched to GCP config: $config${_c_reset}"
  cloud-status
}

# Layer AWS auth on top of current shell
add-aws() {
  local profile="${1:-}"
  if [[ -z "$profile" ]]; then
    echo -e "${_c_yellow}Usage: add-aws <profile>${_c_reset}"
    echo ""
    echo "Available AWS profiles:"
    grep -E '^\[profile ' ~/.aws/config 2>/dev/null | sed 's/\[profile /  /g; s/\]//g'
    return 1
  fi

  local region=$(aws configure get region --profile "$profile" 2>/dev/null || echo "us-east-1")
  local account_id=$(aws configure get sso_account_id --profile "$profile" 2>/dev/null)

  export AWS_PROFILE="$profile"
  export AWS_REGION="$region"
  [[ -n "$account_id" ]] && export AWS_ACCOUNT_ID="$account_id"

  echo -e "${_c_yellow}Adding AWS: $profile${_c_reset}"

  if ! aws sts get-caller-identity --profile "$profile" &>/dev/null; then
    echo -e "${_c_yellow}AWS token expired, authenticating...${_c_reset}"
    aws sso login --profile "$profile"
  fi

  aws sts get-caller-identity --profile "$profile" --output table
  echo -e "${_c_green}AWS layer added: $profile${_c_reset}"
}

# Layer GCP auth on top of current shell
add-gcp() {
  local config="${1:-}"
  if [[ -z "$config" ]]; then
    echo -e "${_c_blue}Usage: add-gcp <config>${_c_reset}"
    echo ""
    echo "Available GCP configs:"
    gcloud config configurations list --format='table(name,is_active,properties.core.account,properties.core.project)' 2>/dev/null
    return 1
  fi

  gcloud config configurations activate "$config" 2>/dev/null || {
    echo -e "${_c_red}Config '$config' not found${_c_reset}"
    return 1
  }

  local account=$(gcloud config get-value account 2>/dev/null)
  local project=$(gcloud config get-value project 2>/dev/null)

  export CLOUDSDK_ACTIVE_CONFIG_NAME="$config"
  export CLOUDSDK_CORE_PROJECT="$project"

  echo -e "${_c_blue}Adding GCP: $config ($project)${_c_reset}"

  if ! gcloud auth print-access-token --account "$account" &>/dev/null 2>&1; then
    echo -e "${_c_blue}GCP token expired, authenticating...${_c_reset}"
    gcloud auth login --account "$account" --update-adc
  fi

  gcloud config list --format='table(core.account,core.project)'
  echo -e "${_c_green}GCP layer added: $config${_c_reset}"
}

# ECR login helper
ecr-login() {
  local region="${1:-$AWS_REGION}"
  local account="${2:-$AWS_ACCOUNT_ID}"

  if [[ -z "$region" ]] || [[ -z "$account" ]]; then
    echo "Usage: ecr-login [region] [account_id]"
    echo "Or set AWS_REGION and AWS_ACCOUNT_ID env vars"
    return 1
  fi

  echo -e "${_c_yellow}Logging into ECR: ${account}.dkr.ecr.${region}.amazonaws.com${_c_reset}"
  aws ecr get-login-password --region "$region" --profile "$AWS_PROFILE" | \
    docker login --username AWS --password-stdin "${account}.dkr.ecr.${region}.amazonaws.com"
}

# GCR/Artifact Registry login helper
gcr-login() {
  local registry="${1:-gcr.io}"
  echo -e "${_c_blue}Logging into GCR: ${registry}${_c_reset}"
  gcloud auth configure-docker "$registry" --quiet
}

# Artifact Registry login (newer GCP)
gar-login() {
  local region="${1:-us}"
  echo -e "${_c_blue}Logging into Artifact Registry: ${region}-docker.pkg.dev${_c_reset}"
  gcloud auth configure-docker "${region}-docker.pkg.dev" --quiet
}

# K8s helpers
kns() {
  # Quick namespace switch
  local ns="${1:-}"
  if [[ -z "$ns" ]]; then
    kubens
  else
    kubens "$ns"
  fi
}

kctx() {
  # Quick context switch
  local ctx="${1:-}"
  if [[ -z "$ctx" ]]; then
    kubectx
  else
    kubectx "$ctx"
  fi
}

# Show help
cloud-help() {
  echo -e "${_c_cyan}Cloud Auth Helper Commands${_c_reset}"
  echo ""
  echo -e "${_c_yellow}Status & Info:${_c_reset}"
  echo "  cloud-status   - Show current auth status for all clouds"
  echo "  cloud-whoami   - Show identities across all clouds"
  echo "  cloud-help     - Show this help"
  echo ""
  echo -e "${_c_yellow}Layer Clouds (add to current shell):${_c_reset}"
  echo "  add-aws <profile>  - Add AWS auth layer"
  echo "  add-gcp <config>   - Add GCP auth layer"
  echo ""
  echo -e "${_c_yellow}Switch (replace current):${_c_reset}"
  echo "  aws-switch <profile>  - Switch AWS profile"
  echo "  gcp-switch <config>   - Switch GCP configuration"
  echo "  cloud-refresh         - Refresh all credentials"
  echo ""
  echo -e "${_c_yellow}Container Registry:${_c_reset}"
  echo "  ecr-login      - Login to AWS ECR"
  echo "  gcr-login      - Login to Google Container Registry"
  echo "  gar-login      - Login to Google Artifact Registry"
  echo ""
  echo -e "${_c_yellow}Kubernetes:${_c_reset}"
  echo "  kns [ns]       - List or switch namespace"
  echo "  kctx [ctx]     - List or switch context"
}

# Aliases
alias cs='cloud-status'
alias cw='cloud-whoami'
alias cr='cloud-refresh'
