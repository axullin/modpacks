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
  groups.toml      AutoModpack groups players can turn off (see Distributing to players)
checks/            `nix flake check` scripts
lib/automodpack.nix  builds AutoModpack's host-modpack and server.conf from groups.toml
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

## Checking the pack

After changing a pack, and always after `packwiz update`, run:

```sh
nix flake check
```

It builds every pack and runs `checks/fabric-depcheck.py` on the fetched mods, which
approximates Fabric Loader's dependency resolution for the pack's loader, Minecraft and
Java version (`javaVersion` in `flake.nix`). It fails on:

- `MISSING`: a mod depends on something no mod provides
- `VERSION`: a dependency is present, but outside the version range a mod needs
  (including the Fabric Loader, Minecraft and Java version)
- `BREAKS`: a mod declares it breaks with a version that is in the pack
- `BYTECODE`: a mod is compiled for a newer Java than the server runs. Fabric does not
  catch this, the game crashes when the class is loaded

It cannot catch a mod using a class that another mod removed in an update (mod metadata
does not say which classes it uses). If the server still crashes after an update, find the
mod in the stack trace, roll it back to the previous version and `packwiz pin` it.

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

Packs with a `groups.toml` also produce the files AutoModpack hosts (see
[Distributing to players](#distributing-to-players)):

- `<pack>-host-modpack`, the tree for `automodpack/host-modpack/`. AutoModpack v5 refuses
  symlinks there, so copy it (nix-minecraft's `files` does) instead of symlinking it.
- `<pack>-automodpack-conf`, the generated `automodpack/server.conf`

Example with nix-minecraft:

```nix
let
  packages = inputs.modpacks.packages.${pkgs.stdenv.hostPlatform.system};
  modpack = packages.nivel-server;
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
    files = {
      "automodpack/server.conf" = packages.nivel-automodpack-conf;
      "automodpack/host-modpack" = packages.nivel-host-modpack;
    };
  };
}
```

## Distributing to players

The `nivel` pack includes [AutoModpack](https://modrinth.com/mod/automodpack) (v5). The
server hosts the client mods, resource packs, shader packs and `defaults/` under
`automodpack/host-modpack/`, and players only need Fabric plus AutoModpack installed;
everything else is downloaded when they join.

`<pack>/groups.toml` defines AutoModpack groups that players can turn off from the
**Modpacks** button in the multiplayer screen (Pack groups). Only client-side mods can be
listed there; anything not listed stays required. Every resource pack and shader pack gets
its own group automatically. The flake reads this file and generates
`<pack>-automodpack-conf` and `<pack>-host-modpack` from it, and a mistake in it (an
unknown group in `requires`, a mod that has to stay required) fails the evaluation.

Players can also import the pack into a launcher that supports packwiz (Prism Launcher via
packwiz-installer) using the raw URL of `pack/pack.toml`.
