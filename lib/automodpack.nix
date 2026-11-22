# AutoModpack (v5) files for a pack: the host-modpack tree and server.conf.
# Optional groups come from <pack>/groups.toml, see "Distributing to players" in the README.
{
  lib,
  linkFarm,
  writeText,
  collectFilesAt,
  name,
  displayName,
  root,
  client,
}:
let
  defaults = "${root}/defaults";

  # { "a" = x; } -> { "<prefix>a" = x; }
  prefixNames = prefix: lib.mapAttrs' (file: lib.nameValuePair "${prefix}${file}");

  clientFiles =
    collectFilesAt client "mods"
    // collectFilesAt client "resourcepacks"
    // collectFilesAt client "shaderpacks";

  readPackEntry = dir: slug: lib.importTOML "${root}/pack/${dir}/${slug}.pw.toml";

  listPackSlugs =
    dir:
    lib.pipe "${root}/pack/${dir}" [
      builtins.readDir
      lib.attrNames
      (lib.filter (lib.hasSuffix ".pw.toml"))
      (map (lib.removeSuffix ".pw.toml"))
    ];

  groupsToml = lib.importTOML "${root}/groups.toml";

  modFile =
    groupId: group: slug:
    let
      entry = readPackEntry "mods" slug;
    in
    assert lib.assertMsg (entry.side == "client" || group.client-optional or false)
      "groups.toml: ${slug} in group ${groupId} is not a client-side mod, it must stay required (or set client-optional if clients can join without it)";
    "mods/${entry.filename}";

  modGroups = lib.mapAttrs (groupId: group: {
    inherit (group) category display-name description;
    requires = group.requires or [ ];
    files = map (modFile groupId group) group.mods;
  }) groupsToml.groups;

  # Every resource pack and shader pack gets a group of its own
  packGroups =
    {
      dir,
      prefix,
      category,
      requires,
    }:
    lib.listToAttrs (
      map (
        slug:
        let
          entry = readPackEntry dir slug;
        in
        lib.nameValuePair "${prefix}-${slug}" {
          inherit category;
          display-name = entry.name;
          description = "";
          requires = requires slug;
          files = [ "${dir}/${entry.filename}" ];
        }
      ) (listPackSlugs dir)
    );

  optionalGroups =
    modGroups
    // packGroups {
      dir = "resourcepacks";
      prefix = "rp";
      category = "ResourcePacks";
      requires = slug: groupsToml.resourcepacks.${slug} or [ ];
    }
    // packGroups {
      dir = "shaderpacks";
      prefix = "shader";
      category = "ShaderPacks";
      requires = _: groupsToml.shaderpacks.requires or [ ];
    };

  optionalFiles = lib.concatMap (group: group.files) (lib.attrValues optionalGroups);

  clientFile =
    groupId: file:
    assert lib.assertMsg (
      clientFiles ? ${file}
    ) "AutoModpack group ${groupId}: ${file} is not in the client pack";
    clientFiles.${file};

  groupFiles = lib.concatMapAttrs (
    groupId: group: prefixNames "${groupId}/" (lib.genAttrs group.files (clientFile groupId))
  ) optionalGroups;

  # server.conf is HOCON, JSON strings and lists are valid in it
  hoconList = values: "[ ${lib.concatMapStringsSep ", " builtins.toJSON values} ]";

  renderGroup =
    groupId: group:
    assert lib.assertMsg (lib.all (dep: optionalGroups ? ${dep})
      group.requires
    ) "AutoModpack group ${groupId} requires an unknown group: ${toString group.requires}";
    ''
      ${groupId} {
        display-name: ${builtins.toJSON group.display-name}
        description: ${builtins.toJSON group.description}
        selection: RECOMMENDED
        requires: ${hoconList group.requires}
      }
    '';

  renderCategory = category: groupIds: ''
    ${category} {
    ${lib.concatMapStrings (groupId: renderGroup groupId optionalGroups.${groupId}) groupIds}
    }
  '';

  groupsByCategory = lib.groupBy (groupId: optionalGroups.${groupId}.category) (
    lib.attrNames optionalGroups
  );

  mainFromServer = [
    "mods/*.jar"
    "kubejs/**"
    "emotes/*"
  ];

  mainExclude = [
    "**/.*"
    "**/.*/**"
    "**/*.{tmp,disabled,bak}"
    "kubejs/server_scripts/**"
  ];

  mainEditable = [
    "options.txt"
    "config/**"
  ];
in
{
  # AutoModpack v5 refuses symlinks in host-modpack, so the server has to copy
  # this tree (dereferenced) into automodpack/host-modpack
  hostModpack = linkFarm "${name}-host-modpack" (
    prefixNames "main/" (removeAttrs clientFiles optionalFiles)
    // groupFiles
    // prefixNames "main/" (collectFilesAt defaults "config")
    // {
      "main/options.txt" = "${defaults}/options.txt";
    }
  );

  serverConf = writeText "automodpack-server.conf" ''
    modpack {
      name: ${builtins.toJSON displayName}

      General {
        main {
          selection: REQUIRED
          from-server: ${hoconList mainFromServer}
          exclude: ${hoconList mainExclude}
          editable: ${hoconList mainEditable}
        }
      }

    ${lib.concatStrings (lib.mapAttrsToList renderCategory groupsByCategory)}
    }
  '';
}
