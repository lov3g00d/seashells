{
  description = "Cloud authentication shell for AWS, GCP, Azure";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs = {
    nixpkgs,
    systems,
    ...
  }: let
    forEachSystem = nixpkgs.lib.genAttrs (import systems);
  in {
    formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

    devShells = forEachSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      cloudTool = pkgs.writeShellScriptBin "cloud" ''
                set -euo pipefail

                AWS_CONFIG="''${AWS_CONFIG:-$HOME/.aws/config}"
                GCP_CONFIG_DIR="''${GCP_CONFIG_DIR:-$HOME/.config/gcloud/configurations}"
                AZURE_DIR="''${AZURE_DIR:-$HOME/.azure}"

                get_aws() { grep -oP '(?<=^\[profile )[^\]]+' "$AWS_CONFIG" 2>/dev/null || true; }
                get_gcp() { for f in "$GCP_CONFIG_DIR"/config_*; do [[ -f "$f" ]] && basename "$f" | sed 's/config_//'; done 2>/dev/null | grep -v default || true; }
                get_azure() { [[ -f "$AZURE_DIR/azureProfile.json" ]] && jq -r '.subscriptions[].name' "$AZURE_DIR/azureProfile.json" 2>/dev/null || true; }

                aws_login() {
                  local p="$1"
                  export AWS_PROFILE="$p"
                  export AWS_REGION=$(aws configure get region --profile "$p" 2>/dev/null || echo "us-east-1")
                  echo -e "\033[0;33m▸ AWS: $p\033[0m"
                  aws sts get-caller-identity --profile "$p" &>/dev/null || aws sso login --profile "$p"
                  aws sts get-caller-identity --profile "$p" --output table
                }

                gcp_login() {
                  local c="$1"
                  gcloud config configurations activate "$c" 2>/dev/null
                  local acct=$(gcloud config get-value account 2>/dev/null)
                  local proj=$(gcloud config get-value project 2>/dev/null)
                  export CLOUDSDK_ACTIVE_CONFIG_NAME="$c" CLOUDSDK_CORE_PROJECT="$proj"
                  echo -e "\033[0;34m▸ GCP: $c ($proj)\033[0m"
                  gcloud auth print-access-token &>/dev/null 2>&1 || gcloud auth login --account "$acct" --update-adc
                  gcloud config list --format='table(core.account,core.project)'
                }

                azure_login() {
                  local s="$1"
                  echo -e "\033[0;36m▸ Azure: $s\033[0m"
                  az account show &>/dev/null || az login
                  az account set --subscription "$s"
                  export AZURE_SUBSCRIPTION="$s"
                  az account show --output table
                }

                fzf_select() {
                  local aws=$(get_aws) gcp=$(get_gcp) azure=$(get_azure)
                  local clouds=()
                  [[ -n "$aws" ]] && clouds+=("AWS")
                  [[ -n "$gcp" ]] && clouds+=("GCP")
                  [[ -n "$azure" ]] && clouds+=("Azure")
                  [[ ''${#clouds[@]} -eq 0 ]] && { echo "No cloud configs found"; exit 1; }

                  local provider=$(printf '%s\n' "''${clouds[@]}" | fzf --header='Select Cloud' --height=30% --reverse --border) || exit 0
                  local items
                  case "$provider" in
                    AWS) items="$aws" ;;
                    GCP) items="$gcp" ;;
                    Azure) items="$azure" ;;
                  esac

                  local selected=$(echo "$items" | fzf --header="$provider profiles" --height=40% --reverse --border) || exit 0
                  case "$provider" in
                    AWS) aws_login "$selected" ;;
                    GCP) gcp_login "$selected" ;;
                    Azure) azure_login "$selected" ;;
                  esac
                }

                status() {
                  echo -e "\033[0;36m=== Cloud Status ===\033[0m"
                  [[ -n "''${AWS_PROFILE:-}" ]] && { echo -e "\033[0;33mAWS:\033[0m $AWS_PROFILE"; aws sts get-caller-identity --profile "$AWS_PROFILE" 2>/dev/null || echo "  ✗ Not authenticated"; }
                  [[ -n "''${CLOUDSDK_ACTIVE_CONFIG_NAME:-}" ]] && { echo -e "\033[0;34mGCP:\033[0m $CLOUDSDK_ACTIVE_CONFIG_NAME"; gcloud auth print-access-token &>/dev/null && echo "  ✓ Authenticated" || echo "  ✗ Not authenticated"; }
                  [[ -n "''${AZURE_SUBSCRIPTION:-}" ]] && { echo -e "\033[0;36mAzure:\033[0m $AZURE_SUBSCRIPTION"; az account show &>/dev/null && echo "  ✓ Authenticated" || echo "  ✗ Not authenticated"; }
                  command -v kubectl &>/dev/null && echo -e "\033[0;35mK8s:\033[0m $(kubectl config current-context 2>/dev/null || echo 'none')"
                }

                add_aws() {
                  local name="''${1:-}"
                  [[ -z "$name" ]] && { echo "Usage: cloud add aws <profile-name>"; return 1; }

                  echo -e "\033[0;33m▸ Creating AWS SSO profile: $name\033[0m"
                  read -rp "SSO Start URL: " sso_url
                  read -rp "SSO Region [us-east-1]: " sso_region
                  sso_region="''${sso_region:-us-east-1}"
                  read -rp "Account ID: " account_id
                  read -rp "Role Name: " role_name
                  read -rp "Default Region [us-east-1]: " region
                  region="''${region:-us-east-1}"

                  mkdir -p "$(dirname "$AWS_CONFIG")"
                  cat >> "$AWS_CONFIG" <<AWSEOF

        [profile $name]
        sso_start_url = $sso_url
        sso_region = $sso_region
        sso_account_id = $account_id
        sso_role_name = $role_name
        region = $region
        output = json
        AWSEOF

                  echo -e "\033[0;32m✓ Profile '$name' created\033[0m"
                  read -rp "Login now? [Y/n]: " login_now
                  [[ "''${login_now:-y}" =~ ^[Yy]?$ ]] && aws_login "$name"
                }

                add_gcp() {
                  local name="''${1:-}"
                  [[ -z "$name" ]] && { echo "Usage: cloud add gcp <config-name>"; return 1; }

                  echo -e "\033[0;34m▸ Creating GCP configuration: $name\033[0m"
                  gcloud config configurations create "$name"

                  read -rp "Project ID: " project_id
                  [[ -n "$project_id" ]] && gcloud config set project "$project_id"

                  read -rp "Default Region: " region
                  [[ -n "$region" ]] && gcloud config set compute/region "$region"

                  echo -e "\033[0;32m✓ Configuration '$name' created\033[0m"
                  read -rp "Login now? [Y/n]: " login_now
                  [[ "''${login_now:-y}" =~ ^[Yy]?$ ]] && gcloud auth login --update-adc
                }

                add_azure() {
                  echo -e "\033[0;36m▸ Azure login\033[0m"
                  az login

                  echo ""
                  echo "Available subscriptions:"
                  az account list --output table

                  read -rp "Set default subscription (name or ID): " sub
                  [[ -n "$sub" ]] && az account set --subscription "$sub"
                  echo -e "\033[0;32m✓ Default subscription set\033[0m"
                  az account show --output table
                }

                case "''${1:-}" in
                  "") fzf_select ;;
                  aws) [[ -z "''${2:-}" ]] && { echo "AWS:"; get_aws | sed 's/^/  /'; } || aws_login "$2" ;;
                  gcp) [[ -z "''${2:-}" ]] && { echo "GCP:"; get_gcp | sed 's/^/  /'; } || gcp_login "$2" ;;
                  azure|az) [[ -z "''${2:-}" ]] && { echo "Azure:"; get_azure | sed 's/^/  /'; } || azure_login "$2" ;;
                  status|s) status ;;
                  add)
                    case "''${2:-}" in
                      aws) add_aws "$3" ;;
                      gcp) add_gcp "$3" ;;
                      azure|az) add_azure ;;
                      *) echo "Usage: cloud add <aws|gcp|azure> [name]" ;;
                    esac
                    ;;
                  help|-h|--help)
                    cat <<EOF
        cloud - Cloud authentication tool

        Usage:
          cloud              Interactive fzf selector
          cloud aws [name]   AWS profiles (list or login)
          cloud gcp [name]   GCP configs (list or login)
          cloud azure [name] Azure subscriptions (list or login)
          cloud status       Show auth status

          cloud add aws <name>   Create new AWS SSO profile
          cloud add gcp <name>   Create new GCP configuration
          cloud add azure        Login and set Azure subscription
        EOF
                    ;;
                  *) echo "Unknown: $1. Try 'cloud help'"; exit 1 ;;
                esac
      '';

      helpers = pkgs.writeTextFile {
        name = "cloud-helpers";
        text = builtins.readFile ./lib/helpers.sh;
      };
    in {
      default = pkgs.mkShell {
        name = "cloud-auth";
        packages = with pkgs; [
          awscli2
          google-cloud-sdk
          azure-cli
          terraform
          kubectl
          kubectx
          kubernetes-helm
          k9s
          stern
          jq
          fzf
          cloudTool
        ];

        shellHook = ''
          source ${helpers}
          echo -e "\033[0;36mCloud Auth Shell\033[0m"
          echo ""
          echo "  cloud           - Interactive fzf selector"
          echo "  cloud status    - Show auth status"
          echo "  cloud-help      - All helper commands"
        '';
      };
    });
  };
}
