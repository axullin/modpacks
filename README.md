# modpacks

Modpacks for my Minecraft servers. Each modpack is a [packwiz](https://packwiz.infra.link/)
pack plus a few extra directories for configs and datapacks. The repo is also a Nix flake,
so the packs can be pulled straight into a NixOS config that uses
[nix-minecraft](https://github.com/Infinidoge/nix-minecraft).

Current packs:

| Pack    | Minecraft | Loader         |
| ------- | --------- | -------------- |
| `nivel` | 1.21.1    | Fabric 0.19.5  |

## Layout

```
<pack>/
  pack/            packwiz pack (pack.toml, index.toml, mods/, resourcepacks/, shaderpacks/)
  defaults/        default client files (config/, options.txt), handed out to players
  server-config/   configs that only belong on the server
  datapacks/       datapacks copied into the world's datapacks folder
flake.nix          builds every pack into a Nix package
```

Only `pack/` is managed by packwiz. The other directories are plain files that the server
config links into place.

## Requirements

- [packwiz](https://packwiz.infra.link/installation/) for editing packs
- Nix with flakes enabled (optional, but `nix develop` gives you packwiz)

```sh
nix develop    # shell with packwiz available
```

All packwiz commands below are run from inside a pack's `pack/` directory, e.g.
`cd nivel/pack`.

## Adding mods

From Modrinth (preferred):

```sh
packwiz modrinth add \<mod name\>
packwiz modrinth add https://modrinth.com/mod/ \<mod name\>
```

From CurseForge:

```sh
packwiz curseforge add \<mod name>
```

packwiz picks the newest version matching the pack's Minecraft version and loader, and
offers to add any required dependencies. Resource packs and shader packs are added the same
way; packwiz puts them in `resourcepacks/` or `shaderpacks/` based on the project type.

### Client-only and server-only mods

Each mod file (`mods/<name>.pw.toml`) has a `side` field: `client`, `server` or `both`.
packwiz fills it in from the mod's metadata, but it is often wrong or missing, so check it.
Rendering, UI and shader mods should be `client`, otherwise the server will try to load
them and crash.

### Other common commands

```sh
packwiz list                 # list everything in the pack
packwiz update <name>        # update one mod
packwiz update --all         # update everything
packwiz remove <name>        # remove a mod
packwiz pin <name>           # keep a mod on its current version
packwiz refresh              # rebuild index.toml after editing files by hand
```

## Updating the Nix hashes

The flake fetches mods as a fixed-output derivation, so every pack has one hash per side in
`flake.nix`. Any change to the pack (adding, removing or updating anything) changes these
hashes, and the build fails until they are updated:

1. Set the hash you need to update to `""` (or `lib.fakeHash`) in `flake.nix`.
2. Build it, e.g. `nix build .#nivel-server`.
3. Copy the `got: sha256-...` value from the error into `flake.nix`.
4. Repeat for the other side (`.#nivel-client`).

## Creating a new modpack

1. Create the pack:

   ```sh
   mkdir -p mypack/pack && cd mypack/pack
   packwiz init
   ```

   It asks for a name, author, version, Minecraft version and loader. Pick the loader
   version that the server will run.

2. Add mods as described above.

3. Optionally create `defaults/`, `server-config/` and `datapacks/` next to `pack/` for
   configs and datapacks.

4. Register it in `flake.nix`:

   ```nix
   modpacks = {
     nivel = { ... };
     mypack = {
       server = "";
       client = "";
     };
   };
   ```

5. `git add` the new files (flakes only see tracked files) and fill in the hashes as
   described in [Updating the Nix hashes](#updating-the-nix-hashes).

## Using the flake

Add the repo as an input:

```nix
inputs.modpacks = {
  url = "github:axullin/modpacks";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Every pack produces two packages, `<pack>-server` and `<pack>-client`, containing the
fetched `mods/`, `resourcepacks/` and `shaderpacks/`. They also expose:

- `loaderVersion` and `minecraftVersion`, read from `pack.toml`
- `root`, the pack's directory in this repo (for `defaults/`, `server-config/`, `datapacks/`)

Example with nix-minecraft:

```nix
let
  modpack = inputs.modpacks.packages.${pkgs.stdenv.hostPlatform.system}.nivel-server;
in
{
  services.minecraft-servers.servers.nivel = {
    enable = true;
    package = pkgs.fabricServers.fabric-1_21_1.override {
      inherit (modpack) loaderVersion;
    };
    symlinks = {
      mods = "${modpack}/mods";
      "config/mobcontrol.toml" = "${modpack.root}/server-config/mobcontrol.toml";
    };
  };
}
```

## Distributing to players

The `nivel` pack includes [AutoModpack](https://modrinth.com/mod/automodpack). The server
hosts the client mods, resource packs, shader packs and `defaults/` under
`automodpack/host-modpack/main/`, and players only need Fabric plus AutoModpack installed;
everything else is downloaded when they join.

Players can also import the pack into a launcher that supports packwiz (Prism Launcher via
packwiz-installer) using the raw URL of `pack/pack.toml`.
