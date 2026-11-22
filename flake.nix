{
  description = "Packwiz modpacks for my Minecraft servers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-minecraft,
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Fixed-output hashes of the fetched mod sets, one per side.
      # These must be updated whenever the pack's contents change (see README).
      modpacks = {
        nivel = {
          server = "sha256-/Ax4kjazUfSK6Ko6gps2xIAD6mCLdRPDszysGR6Rb9M=";
          client = "sha256-Axczhdow7kRzmd+FaFqe4am1/vcMCpisKpl6KD6HqoM=";
        };
      };

      # Java the server runs on (nix-minecraft's JRE for 1.21.1), clients are expected to match
      javaVersion = "21";

      mkModpack =
        pkgs: name: side: packHash:
        let
          src = ./${name}/pack;
          pack = lib.importTOML (src + "/pack.toml");
          inherit (nix-minecraft.legacyPackages.${pkgs.stdenv.hostPlatform.system}) fetchPackwizModpack;
        in
        (fetchPackwizModpack {
          inherit src side packHash;
          pname = "${name}-modpack-${side}";
          inherit (pack) version;
        }).overrideAttrs
          (previous: {
            passthru = previous.passthru // {
              loaderVersion = pack.versions.fabric;
              minecraftVersion = pack.versions.minecraft;
              # Non-packwiz files that live next to the pack
              root = ./${name};
            };
          });
    in
    {
      packages = forAllSystems (
        pkgs:
        lib.concatMapAttrs (
          name: hashes:
          lib.mapAttrs' (
            side: hash: lib.nameValuePair "${name}-${side}" (mkModpack pkgs name side hash)
          ) hashes
        ) modpacks
      );

      # Approximates Fabric's dependency resolution on every built mod set,
      # so broken updates fail `nix flake check` instead of the server
      checks = forAllSystems (
        pkgs:
        lib.mapAttrs' (
          name: modpack:
          lib.nameValuePair "${name}-dependencies" (
            pkgs.runCommand "${name}-dependencies" { nativeBuildInputs = [ pkgs.python3 ]; } ''
              python3 -I ${./checks/fabric-depcheck.py} ${modpack}/mods \
                ${modpack.loaderVersion} ${modpack.minecraftVersion} ${javaVersion}
              touch $out
            ''
          )
        ) self.packages.${pkgs.stdenv.hostPlatform.system}
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell { packages = [ pkgs.packwiz ]; };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
