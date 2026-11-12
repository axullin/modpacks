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
          server = "sha256-4Ggm0MrgLgz4V+35xEwlnqHP3VQbg7PN2WcBVs2v78c=";
          client = "sha256-8/P/xwjmaj6S3A9bKAHr/X+mriS0m48BhCzV82JhBVU=";
        };
      };

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

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell { packages = [ pkgs.packwiz ]; };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
