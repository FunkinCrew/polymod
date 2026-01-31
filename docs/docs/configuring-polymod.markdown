---
title: Configuring Polymod
---
{% include toc.html %}

# Configuring Polymod

It may be that the default settings are not suitable for your needs. This document will provide all the available options you can configure in your project.

## Compiler Configuration

The first type of configuration available for Polymod is the compiler options. You can set these values in your `project.xml` file using a `haxedef` tag. You can also modify the appropriate property in `PolymodConfig` in your code before initializing Polymod, although this is not recommended.

The available options are:

- `POLYMOD_DEBUG`: If `true`, additional debug output will be provided by Polymod.
    - Defaults to `false`.
- `POLYMOD_ROOT_PATH`: The base path from which scripts should be accessed.
    - Defaults to `data/`
- `POLYMOD_USE_NAMESPACE`: Whether script paths should, by default, be relative to the class's path or the root path.
    - For example, if true, `demo.Simulation#updateBee` will use `data/demo/Simulation/updateBee.txt`
    - If false, `demo.Simulation#updateBee` will use `data/updateBee.txt`
- `POLYMOD_SCRIPT_EXT`: The file extension used for script files.
    - Defaults to `.txt`.
    - The default option is in place for compatibility reasons, you'll probably want to change it to `.hscript` or something similar.
- `POLYMOD_SCRIPT_LIBRARY`: The asset library to load scripts from.
    - Defaults to `default`.
    - Only relevant for Lime and OpenFL/HaxeFlixel projects which utilize multiple asset libraries.
- `POLYMOD_API_VERSION_MATCH`: Determines the precision required for
    - Possible values are `NONE` (no version matching required), `MATCH_MAJOR` (major version must match), `MATCH_MINOR` (major and minor version must match), or `MATCH_PATCH` (major, minor, and patch version must match).
    - Defaults to `MATCH_PATCH`.
    - The default option is in place for compatibility reasons, you'll probably want to change it to `MATCH_MINOR` or higher.
- `POLYMOD_APPEND_FOLDER`: Set this value to change the directory which append files are read from.
    - Defaults to `_append`
- `POLYMOD_MERGE_FOLDER`: Set this value to change the directory which merge files are read from.
    - Defaults to `_merge`
- `POLYMOD_MOD_METADATA_FILE`: Set this value to change the file Polymod uses for mod metadata.
    - Defaults to `_polymod_meta.json`
- `POLYMOD_MOD_PACK_FILE`: Set this value to change the file Polymod uses for modpack metadata.
    - Defaults to `_polymod_pack.txt`
- `POLYMOD_MOD_ICON_FILE`: Set this value to change the file Polymod uses for mod icons.
    - Defaults to `_polymod_icon.png`
- `POLYMOD_MOD_IGNORE`: Set this value to change the list of files which Polymod ignores when loading mods.
    - Use a comma separated list of file names.
    - Defaults to `LICENSE.txt,ASSET_LICENSE.txt,CODE_LICENSE.txt`

## Polymod Parameters

The other type of configuration available for Polymod is the parameters which you may provide to Polymod when you initialize your mods.

```haxe
Polymod.init({
    /**
     * The directory path on your file system which contains all your mods.
     */
    modRoot: "./mods",

    /**
     * The list of mods to load by ID,
     * where the ID is the directory name of the mod folder relative to `modRoot`.
     */
    dirs: ["mymod"]

    /**
     * (optional) The framework defines which Haxe framework you're using to load assets, which determines what backend to use.
     * Polymod can attempt to determine this automatically, so only use this option
     * if it has trouble, or you need to specify a custom backend.
     */
    framework: CUSTOM,

    /**
     * (optional) Specify any additional configuration paramters needed for your specific Haxe framework.
     */
    frameworkParams: {
        /**
         * Lime/OpenFL only:
         * If you're using custom or non-default asset libraries, then you must provide a key=>value store
         * mapping the name of each asset library to a path prefix in your mod structure.
         * Thus, assets in the `world1` library go in the `world1` folder within your mod folder, etc.
         */
        assetLibraryPaths: [
            "default" => "./preload",
			"world1" => "./world1"
        ]
    },

    /**
     * (optional) A version string which should conform with Semantic Versioning 2.0 standards.
     * This lets you enforce a modding API for your application.
     * Any mod which is not compatible will gracefully fail to load, allowing you to notify the user that the mod needs to be updated.
     * Note that for a mod to be compatible, it must match in both major, minor, AND patch versions.
     *
     * You should set this to a reasonable value early on, then update it whenever you change how mods interact with your application,
     * including when you change directory structures or modify scripts in a way that introduces breaking changes.
     *
     * @see https://semver.org/
     */
    apiVersion: "1.0.0",

    /**
     * (optional) A function which takes a `PolymodError` as an argument.
     *
     * This is called whenever an error occurs within Polymod; if you do not provide a function to call here,
     * any failures will happen silently.
     */
    errorCallback: onError,

    /**
     * (optional) Allows you to ensure a specific version of a mod is loaded by Polymod.
     *
     * If this array is provided, Polymod will check to see if each mod you attempt to load matches a particular version
     * (as in the mod's own version, not your game/app's modding API version).
     * If any of the mods aren't compatible with the specified version numbers,`errorCallback` will receive a `PARAM_MOD_VERSIONS` error.
     */
    modVersions: ["1.3.0"],

    /**
     * (optional) The parsing rules to use for various data formats.
     * This determines how appending and merging should work for certain file extensions or even specific file names.
     */
    parseRules: getParseRules(),
})
```

For more information on defining parse rules, see [Parse Rules](./parse-rules).
