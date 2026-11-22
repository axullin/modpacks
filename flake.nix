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

      modpacks = {
        nivel = {
          displayName = "Nivel";
          # Fixed-output hashes of the fetched mod sets, one per side.
          # These must be updated whenever the pack's contents change (see README).
          hashes = {
            server = "sha256-/Ax4kjazUfSK6Ko6gps2xIAD6mCLdRPDszysGR6Rb9M=";
            client = "sha256-Axczhdow7kRzmd+FaFqe4am1/vcMCpisKpl6KD6HqoM=";
          };
        };
      };

      # Java the server runs on
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

      mkPackages =
        pkgs: name: pack:
        let
          sides = lib.mapAttrs (mkModpack pkgs name) pack.hashes;
          automodpack = pkgs.callPackage ./lib/automodpack.nix {
            inherit (nix-minecraft.lib) collectFilesAt;
            inherit name;
            inherit (pack) displayName;
            inherit (sides) client;
            root = ./${name};
          };
        in
        lib.mapAttrs' (side: lib.nameValuePair "${name}-${side}") sides
        // lib.optionalAttrs (builtins.pathExists ./${name}/groups.toml) {
          "${name}-host-modpack" = automodpack.hostModpack;
          "${name}-automodpack-conf" = automodpack.serverConf;
        };
    in
    {
      packages = forAllSystems (pkgs: lib.concatMapAttrs (mkPackages pkgs) modpacks);

      # Approximates Fabric's dependency resolution on every built mod set,
      # so broken updates fail `nix flake check` instead of the server
      checks = forAllSystems (
        pkgs:
        lib.concatMapAttrs (
          name: pack:
          lib.mapAttrs' (
            side: _:
            let
              modpack = self.packages.${pkgs.stdenv.hostPlatform.system}."${name}-${side}";
            in
            lib.nameValuePair "${name}-${side}-dependencies" (
              pkgs.runCommand "${name}-${side}-dependencies" { nativeBuildInputs = [ pkgs.python3 ]; } ''
                python3 -I ${./checks/fabric-depcheck.py} ${modpack}/mods \
                  ${modpack.loaderVersion} ${modpack.minecraftVersion} ${javaVersion}
                touch $out
              ''
            )
          ) pack.hashes
        ) modpacks
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell { packages = [ pkgs.packwiz ]; };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
