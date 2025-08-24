{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      overlays = [
        (final: prev: rec { })
      ];
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import nixpkgs { inherit overlays system; };
          }
        );
    in
    {
      devShells = forEachSupportedSystem (
        { pkgs }:
        {
          default = pkgs.mkShell {
            packages =
              with pkgs;
              [
                ansible
                ansible-lint
                python311
                virtualenv
                fluxcd
                sops
                age
                cloudflared
                kustomize
                kubectl-cnpg
                openssl
                pre-commit
                nodejs
                prettier
                shellcheck
              ]
              ++ (with pkgs.python311Packages; [
                pip
                netaddr
                ipython
                typos
              ]);
            # shellHook = ''
            #   . <(flux completion zsh)
            # '';
          };
        }
      );
    };
}
