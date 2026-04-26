#!/usr/bin/env bash
set -euo pipefail

# === Config paths (native CLIs are the source of truth) ===
AWS_CONFIG="${AWS_CONFIG:-$HOME/.aws/config}"
GCP_CONFIG_DIR="${GCP_CONFIG_DIR:-$HOME/.config/gcloud/configurations}"
AZURE_PROFILE="${AZURE_PROFILE:-$HOME/.azure/azureProfile.json}"

# === ANSI colors ===
C_AWS=$'\033[33m'     # yellow
C_GCP=$'\033[34m'     # blue
C_AZURE=$'\033[36m'   # cyan
C_K8S=$'\033[35m'     # magenta
C_RESET=$'\033[0m'

# === Discovery ===

discover_aws() {
  [[ -f "$AWS_CONFIG" ]] || return 0
  grep -qP '^\[default\]' "$AWS_CONFIG" 2>/dev/null && echo "aws:default"
  grep -oP '(?<=^\[profile )[^\]]+' "$AWS_CONFIG" 2>/dev/null | while read -r name; do
    echo "aws:$name"
  done
}

discover_gcp() {
  [[ -d "$GCP_CONFIG_DIR" ]] || return 0
  for f in "$GCP_CONFIG_DIR"/config_*; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f" | sed 's/^config_//')
    echo "gcp:$name"
  done
}

discover_azure() {
  [[ -f "$AZURE_PROFILE" ]] || return 0
  jq -r '.subscriptions[].name // empty' "$AZURE_PROFILE" 2>/dev/null | while read -r name; do
    echo "azure:$name"
  done
}

discover_k8s() {
  kubectl config get-contexts -o name 2>/dev/null | while read -r name; do
    echo "k8s:$name"
  done
}

discover_all() {
  discover_aws
  discover_gcp
  discover_azure
  discover_k8s
}

# === Detail (for fzf preview) ===

profile_details() {
  local entry="$1"
  local provider="${entry%%:*}"
  local name="${entry#*:}"

  case "$provider" in
    aws)
      echo "  aws ❯ $name"
      echo ""
      name="$name" awk '
        BEGIN { profile = ENVIRON["name"] }
        /^\[profile / { found = ($0 == "[profile " profile "]") }
        /^\[default\]/ { found = ($0 == "[default]" && profile == "default") }
        found && /^[^[\[]/ && NF { print "  " $0 }
      ' "$AWS_CONFIG" 2>/dev/null
      ;;
    gcp)
      echo "  gcp ❯ $name"
      echo ""
      local cfg="$GCP_CONFIG_DIR/config_$name"
      [[ -f "$cfg" ]] && sed 's/^/  /' "$cfg" 2>/dev/null
      ;;
    azure)
      echo "  azure ❯ $name"
      echo ""
      jq -r --arg name "$name" '.subscriptions[] | select(.name == $name) | to_entries[] | "  \(.key): \(.value)"' "$AZURE_PROFILE" 2>/dev/null
      ;;
    k8s)
      echo "  k8s ❯ ${name##*/}"
      echo ""
      echo "  $name"
      echo ""
      kubectl config get-contexts "$name" 2>/dev/null | sed 's/^/  /'
      ;;
  esac
}

# === Activation ===

login_aws() {
  local name="$1"
  aws sts get-caller-identity --profile "$name" &>/dev/null || aws sso login --profile "$name" >&2
}

login_gcp() {
  local name="$1"
  gcloud config configurations activate "$name" 2>/dev/null >&2
  gcloud auth print-access-token &>/dev/null 2>&1 || gcloud auth login --update-adc >&2
}

login_azure() {
  local name="$1"
  az account show &>/dev/null || az login >&2
  az account set --subscription "$name" >&2
}

use_profile() {
  local entry="$1"
  local provider name

  if [[ "$entry" == *:* ]]; then
    provider="${entry%%:*}"
    name="${entry#*:}"
  else
    local matches
    matches=$(discover_all | grep ":${entry}$" || true)
    local count
    count=$(echo "$matches" | grep -c . || true)

    if [[ "$count" -eq 0 ]]; then
      echo "Profile not found: $entry" >&2
      return 1
    elif [[ "$count" -gt 1 ]]; then
      echo "Ambiguous name '$entry', matches:" >&2
      echo "$matches" >&2
      echo "Use provider:name format (e.g. aws:$entry)" >&2
      return 1
    fi

    provider="${matches%%:*}"
    name="${matches#*:}"
  fi

  local safe_name
  printf -v safe_name '%q' "$name"

  local label
  label=$(label_for "$provider")

  case "$provider" in
    aws)
      login_aws "$name"
      echo "export AWS_PROFILE=$safe_name"
      local region
      region=$(name="$name" awk '
        BEGIN { profile = ENVIRON["name"] }
        /^\[profile / { found = ($0 == "[profile " profile "]") }
        found && /^region/ { gsub(/^region[[:space:]]*=[[:space:]]*/, ""); print; exit }
      ' "$AWS_CONFIG" 2>/dev/null || true)
      [[ -n "$region" ]] && echo "export AWS_REGION=$region"
      printf '  %s ❯ %s' "$label" "$name" >&2
      [[ -n "$region" ]] && printf ' (%s)' "$region" >&2
      echo "" >&2
      ;;
    gcp)
      login_gcp "$name"
      echo "export CLOUDSDK_ACTIVE_CONFIG_NAME=$safe_name"
      local project
      project=$(awk -F= '/^project/ { gsub(/^ +| +$/, "", $2); print $2; exit }' \
        "$GCP_CONFIG_DIR/config_$name" 2>/dev/null || true)
      [[ -n "$project" ]] && echo "export CLOUDSDK_CORE_PROJECT=$project"
      printf '  %s ❯ %s' "$label" "$name" >&2
      [[ -n "$project" ]] && printf ' (%s)' "$project" >&2
      echo "" >&2
      ;;
    azure)
      login_azure "$name"
      echo "export AZURE_SUBSCRIPTION=$safe_name"
      printf '  %s ❯ %s\n' "$label" "$name" >&2
      ;;
    k8s)
      echo "kubectl config use-context $safe_name"
      printf '  %s ❯ %s\n' "$label" "${name##*/}" >&2
      ;;
    *)
      echo "Unknown provider: $provider" >&2
      return 1
      ;;
  esac
}

# === Commands ===

label_for() {
  case "$1" in
    aws)   printf '%s' "${C_AWS}aws${C_RESET}" ;;
    gcp)   printf '%s' "${C_GCP}gcp${C_RESET}" ;;
    azure) printf '%s' "${C_AZURE}azure${C_RESET}" ;;
    k8s)   printf '%s' "${C_K8S}k8s${C_RESET}" ;;
  esac
}

short_name() {
  local provider="$1" name="$2"
  case "$provider" in
    k8s) echo "${name##*/}" ;;
    *)   echo "$name" ;;
  esac
}

cmd_list() {
  local last_provider=""
  discover_all | while read -r entry; do
    local provider="${entry%%:*}"
    local name="${entry#*:}"
    if [[ "$provider" != "$last_provider" ]]; then
      [[ -n "$last_provider" ]] && echo ""
      case "$provider" in
        aws)   echo "${C_AWS}=== AWS ===${C_RESET}" ;;
        gcp)   echo "${C_GCP}=== GCP ===${C_RESET}" ;;
        azure) echo "${C_AZURE}=== Azure ===${C_RESET}" ;;
        k8s)   echo "${C_K8S}=== Kubernetes ===${C_RESET}" ;;
      esac
      last_provider="$provider"
    fi
    echo "  $(short_name "$provider" "$name")"
  done
}

cmd_current() {
  local out=""
  [[ -n "${AWS_PROFILE:-}" ]] && out+="${C_AWS}aws${C_RESET}:$AWS_PROFILE  "
  [[ -n "${CLOUDSDK_ACTIVE_CONFIG_NAME:-}" ]] && out+="${C_GCP}gcp${C_RESET}:$CLOUDSDK_ACTIVE_CONFIG_NAME  "
  [[ -n "${AZURE_SUBSCRIPTION:-}" ]] && out+="${C_AZURE}azure${C_RESET}:$AZURE_SUBSCRIPTION  "
  local k8s
  k8s=$(kubectl config current-context 2>/dev/null || true)
  [[ -n "$k8s" ]] && out+="${C_K8S}k8s${C_RESET}:${k8s##*/}"
  echo "${out:-none}"
}

cmd_status() {
  echo "=== Cloud ==="
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    echo -n "  ${C_AWS}aws${C_RESET}  $AWS_PROFILE "
    aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null && echo "[ok]" || echo "[expired]"
  fi
  if [[ -n "${CLOUDSDK_ACTIVE_CONFIG_NAME:-}" ]]; then
    echo -n "  ${C_GCP}gcp${C_RESET}  $CLOUDSDK_ACTIVE_CONFIG_NAME "
    gcloud auth print-access-token &>/dev/null 2>&1 && echo "[ok]" || echo "[expired]"
  fi
  if [[ -n "${AZURE_SUBSCRIPTION:-}" ]]; then
    echo -n "  ${C_AZURE}azure${C_RESET}  $AZURE_SUBSCRIPTION "
    az account show &>/dev/null && echo "[ok]" || echo "[expired]"
  fi
  echo "=== Kubernetes ==="
  local k8s
  k8s=$(kubectl config current-context 2>/dev/null || true)
  if [[ -n "$k8s" ]]; then
    echo -n "  ${C_K8S}k8s${C_RESET}  ${k8s##*/} "
    kubectl cluster-info &>/dev/null 2>&1 && echo "[ok]" || echo "[unreachable]"
  else
    echo "  none"
  fi
}

cmd_refresh() {
  [[ -n "${AWS_PROFILE:-}" ]] && { echo "Refreshing AWS..." >&2; aws sso login --profile "$AWS_PROFILE" >&2; }
  [[ -n "${CLOUDSDK_ACTIVE_CONFIG_NAME:-}" ]] && { echo "Refreshing GCP..." >&2; gcloud auth login --update-adc >&2; }
  [[ -n "${AZURE_SUBSCRIPTION:-}" ]] && { echo "Refreshing Azure..." >&2; az login >&2; }
  echo "Done" >&2
}

cmd_pick() {
  local profiles
  profiles=$(discover_all)

  if [[ -z "$profiles" ]]; then
    echo "No profiles found. Configure cloud CLIs first:" >&2
    echo "  aws configure sso --profile <name>" >&2
    echo "  gcloud init --configuration <name>" >&2
    echo "  az login" >&2
    return 1
  fi

  # Build tab-separated lines: colored_display \t provider:name
  local items
  items=$(echo "$profiles" | while read -r entry; do
    local provider="${entry%%:*}"
    local name="${entry#*:}"
    local display
    display=$(short_name "$provider" "$name")
    local label
    label=$(label_for "$provider")
    printf '%s  %s\t%s\n' "$label" "$display" "$entry"
  done)

  local selected
  selected=$(echo "$items" | fzf --ansi \
    --header=$'cloud-auth' \
    --height=60% --reverse --border=rounded \
    --delimiter=$'\t' --with-nth=1 \
    --preview="$0 _detail {2}" \
    --preview-window=right:40%:wrap) || return 0

  # Extract provider:name from second tab-separated field
  local entry
  entry="${selected#*	}"

  use_profile "$entry"
}

cmd_help() {
  local B=$'\033[1m' D=$'\033[2m' R=$'\033[0m'
  cat <<EOF

  ${B}☁️  cloud-auth${R} ${D}— multi-cloud & kubernetes profile manager${R}

  Discovers profiles from native CLI configs automatically.

  ${D}SELECT${R}
    ${B}cloud${R}                          pick any profile (fzf)

  ${D}ACTIVATE${R}
    ${B}eval "\$(cloud use <name>)"${R}     activate profile
    ${B}eval "\$(cloud use aws:dev)"${R}    activate with provider prefix

  ${D}INFO${R}
    ${B}cloud ls${R}                       list all profiles
    ${B}cloud current${R}                  active profiles
    ${B}cloud status${R}                   auth status check
    ${B}cloud refresh${R}                  re-auth active sessions

  ${D}SOURCES${R}
    ${C_AWS}aws${R}     ~/.aws/config
    ${C_GCP}gcp${R}     ~/.config/gcloud/configurations/
    ${C_AZURE}azure${R}   ~/.azure/azureProfile.json
    ${C_K8S}k8s${R}     kubectl config get-contexts

EOF
}

# === Main ===

case "${1:-}" in
  "")              cmd_pick ;;
  ls|list)         cmd_list ;;
  use|u)           shift; if [[ -z "${1:-}" ]]; then cmd_pick; else use_profile "$1"; fi ;;
  current|c)       cmd_current ;;
  status|s)        cmd_status ;;
  refresh|r)       cmd_refresh ;;
  help|-h|--help)  cmd_help ;;
  _detail)         shift; [[ -n "${1:-}" ]] && profile_details "$1" ;;
  *)               echo "Unknown: $1. Try 'cloud help'" >&2; exit 1 ;;
esac
