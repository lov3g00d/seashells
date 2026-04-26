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

      cloudTool = pkgs.writeShellApplication {
        name = "cloud";
        runtimeInputs = with pkgs; [
          awscli2
          google-cloud-sdk
          azure-cli
          kubectl
          jq
          fzf
          gawk
        ];
        text = builtins.readFile ./cloud.sh;
      };
    in {
      default = pkgs.mkShell {
        name = "cloud-auth";
        packages = with pkgs; [
          cloudTool
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
          gawk
          starship
        ];

        shellHook = ''
          export SEASHELL="☁️ cloud"

          printf '\n'
          printf '  \033[1;36m☁️  cloud-auth\033[0m\n'
          printf '  \033[2m─────────────────────────────\033[0m\n'
          printf '  \033[1mcloud\033[0m          \033[2mselect profile\033[0m\n'
          printf '  \033[1mcloud ls\033[0m       \033[2mlist profiles\033[0m\n'
          printf '  \033[1mcloud help\033[0m     \033[2mfull help\033[0m\n'
          printf '\n'
        '';
      };
    });
  };
}
