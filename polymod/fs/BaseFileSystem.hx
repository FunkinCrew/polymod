package polymod.fs;

import haxe.io.Bytes;
import polymod.Polymod.ModMetadata;
import polymod.Polymod.PolymodErrorOrigin;
import polymod.fs.PolymodFileSystem.IFileSystem;
import polymod.fs.PolymodFileSystem.PolymodFileSystemParams;
import polymod.util.Util;
import polymod.util.VersionUtil;
import thx.semver.VersionRule;

#if lime
import lime.app.Future;
#end

/**
 * Abstract base class providing partial file system implementations.
 * Extend this and override methods as needed.
 */
abstract class BaseFileSystem implements IFileSystem
{
  /**
   * The directory relative to the application path where mods are located.
   */
  public final modRoot:String;

  /**
   * A cache of the directories containing mod metadata, indexed by mod ID.
   */
  var modMetadataLocations:Map<String, String> = [];

  public function new(params:PolymodFileSystemParams)
  {
    this.modRoot = params.modRoot;
  }

  /**
   * Called when Polymod commands that a mod with the given ID is loaded.
   * @param id The ID of the mod that was loaded.
   */
  public function onLoadMod(id:String):Void {}

  /**
   * Called when Polymod commands that a mod with the given ID is unloaded.
   * @param id The ID of the mod that was unloaded.
   */
  public function onUnloadMod(id:String):Void {}

  /**
   * Return whether the file or directory exists in a specific mod.
   *
   * @param path The path to check.
   * @param modId A specific mod ID to check within.
   * @return Whether the file or directory exists in that mod.
   */
  public function existsByModId(path:String, modId:String):Bool
  {
    var modDir:String = scanModDirectoriesForId(modId) ?? return false;
    var relativeDir:String = Util.pathJoin(modRoot, modDir);

    return exists(Util.pathJoin(relativeDir, path));
  }

  /**
   * Returns a list of files contained within the provided mod directory path.
   *
   * @param modDir The mod path to check.
   * @param recursive Whether to check all subfolder recursively. Returns only files.
   * @return An array of file paths.
   */
  public function readModDirectory(modDir:String, recursive:Bool = true):Array<String>
  {
    return recursive ? readDirectoryRecursive(Util.pathJoin(modRoot, modDir)) : readDirectory(Util.pathJoin(modRoot, modDir));
  }

  /**
   * Returns the content of a given file as a string.
   *
   * @param path The file to read.
   * @return The text content of the file, or `null` if the file can't be found.
   */
  public function getFileContent(path:String):Null<String>
  {
    return getFileBytes(path)?.toString();
  }

  #if lime
  /**
   * Load the byte data for a file asynchronously.
   *
   * @param path The path to retrieve byte data from.
   * @return A future which returns the file bytes.
   */
  public function loadFileBytes(path:String):Future<Bytes>
  {
    var performWork:Void->Bytes = () -> {
      var result = getFileBytes(path);
      if (result == null)
      {
        throw 'Could not load file bytes $path';
      }
      return result;
    };

    return new Future(performWork, true);
  }

  /**
   * Load the byte data for a file from a specific mod, asynchronously.
   *
   * @param path The path to retrieve byte data from, relative to the asset root.
   * @param modId A specific mod ID to retrieve an asset from.
   * @return A future which returns the file bytes.
   */
  public function loadFileBytesByModId(path:String, modId:String):Future<Bytes>
  {
    var modDir:Null<String> = scanModDirectoriesForId(modId);
    if (modDir == null) return null;
    var relativeDir = Util.pathJoin(modRoot, modDir);

    return loadFileBytes(Util.pathJoin(relativeDir, path));
  }
  #end

  /**
   * Get the byte data for a file from a specific mod.
   *
   * @param path The path to retrieve byte data from, relative to the asset root.
   * @param modId A specific mod ID to retrieve an asset from.
   * @return The file bytes, or `null` if it couldn't be fetched.
   */
  public function getFileBytesByModId(path:String, modId:String):Null<Bytes>
  {
    var modDir:String = scanModDirectoriesForId(modId) ?? return null;
    var relativeDir:String = Util.pathJoin(modRoot, modDir);

    return getFileBytes(Util.pathJoin(relativeDir, path));
  }

  /**
   * Provide a list of valid mods for this file system to load.
   *
   * @param apiVersionRule (optional) A version query to match against the mod's API version.
   * @return An array of matching mods.
   */
  public function scanMods(?apiVersionRule:VersionRule):Array<ModMetadata>
  {
    if (apiVersionRule == null) apiVersionRule = VersionUtil.DEFAULT_VERSION_RULE;

    var result:Array<ModMetadata> = [];

    for (modId => modDir in modMetadataLocations)
    {
      if (!hasMetadataFile(modDir))
      {
        // Remove locations that no longer have metadata.
        modMetadataLocations.remove(modId);
        continue;
      }

      var meta:Null<ModMetadata> = this.getMetadataByModDir(modDir, PolymodErrorOrigin.SCAN);
      if (meta == null)
      {
        // Remove locations whose metadata can no longer be parsed.
        modMetadataLocations.remove(modId);
        continue;
      }

      if (!meta.isCompatible(apiVersionRule))
      {
        // Remove locations whose metadata is no longer compatible with the current API version.
        Polymod.warning(
          MOD_API_VERSION_MISMATCH,
          'Mod "${modDir}" is not compatible with API version "${apiVersionRule.toString()}", got "${meta.apiVersion.toString()}"',
          SCAN
        );
        modMetadataLocations.remove(modId);
        continue;
      }

      // Leave the known metadata in place.
      result.push(meta);
    }

    // Now check EVERY directory.
    var knownDirectories:Array<String> = [for (key => value in modMetadataLocations) value];
    var dirsInModRoot:Array<String> = readDirectory(modRoot);
    for (modDir in dirsInModRoot)
    {
      if (knownDirectories.contains(modDir))
      {
        // We've already found mod metadata there.
        continue;
      }

      if (!hasMetadataFile(modDir))
      {
        // No mod metadata there.
        continue;
      }

      var meta:Null<ModMetadata> = this.getMetadataByModDir(modDir, PolymodErrorOrigin.SCAN);
      if (meta == null)
      {
        // Unparsable mod metadata there.
        continue;
      }

      if (!meta.isCompatible(apiVersionRule))
      {
        // Incompatible mod metadata there.
        Polymod.warning(
          MOD_API_VERSION_MISMATCH,
          'Mod "${modDir}" is not compatible with API version "${apiVersionRule.toString()}", got "${meta.apiVersion.toString()}"',
          SCAN
        );
        continue;
      }

      // Found a new mod!
      modMetadataLocations.set(meta.id, modDir);
      result.push(meta);
    }

    return result;
  }

  /**
   * Determines the mod directory associated with a given mod ID.
   *
   * @param modId The ID of the mod to look for.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The directory path where the mod was found, or `null` if not found.
   */
  public function scanModDirectoriesForId(modId:String, ?origin:PolymodErrorOrigin):Null<String>
  {
    // Get the directory that the mod metadata is in from cache.
    var knownDirectory:Null<String> = modMetadataLocations.get(modId);
    if (knownDirectory != null) return knownDirectory;

    // Otherwise, scan all the directories in the mod root.
    for (dir in readDirectory(modRoot))
    {
      var modPath:String = Util.pathJoin(modRoot, dir);
      if (exists(modPath))
      {
        var meta:Null<ModMetadata> = null;

        var metaFile = Util.pathJoin(modPath, PolymodConfig.modMetadataFile);

        if (!exists(metaFile))
        {
          continue;
        }
        else
        {
          var metaText:Null<String> = getFileContent(metaFile);
          if (metaText == null)
          {
            Polymod.warning(MOD_MISSING_METADATA, 'Could not retrieve contents for metadata $metaFile', origin);
            continue;
          }
          meta = ModMetadata.fromJsonStr(metaText, origin);
        }

        if (meta == null) continue;

        modMetadataLocations.set(meta.id, dir);

        if (meta.id != modId && dir != modId) continue;
        meta.dirName = dir;
        meta.modPath = modPath;

        var iconFile = getModIconPath(modPath, origin);
        var iconBytes:Null<Bytes> = getFileBytes(iconFile);
        if (iconBytes == null)
        {
          Polymod.warning(MOD_MISSING_ICON, 'Could not obtain mod icon data from file: $iconFile', origin);
        }
        else
        {
          meta.icon = iconBytes;
          meta.iconPath = iconFile;
        }

        return dir;
      }
    }
    Polymod.error(MOD_MISSING_ID, 'Could not find mod with ID: $modId', origin);
    return null;
  }

  function getModIconPath(modPath:String, ?origin:PolymodErrorOrigin):Null<String>
  {
    for (iconBasePath in PolymodConfig.modIconFile)
    {
      var iconFile = Util.pathJoin(modPath, iconBasePath);

      if (!exists(iconFile)) continue;

      return iconFile;
    }

    Polymod.warning(MOD_MISSING_ICON, 'Could not find any mod icons for mod: $modPath', origin);
    return null;
  }

  /**
   * Get the metadata for a given mod.
   * This function is DEPRECATED, use `getMetadataByModDir` for the same result.
   *
   * @param dirName The directory name of the mod.
   * @param origin The error reporting origin.
   * @return The mod metadata, or `null` if not found.
   */
  @:deprecated('getMetadata is deprecated, use getMetadataByModDir')
  public function getMetadata(dirName:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return getMetadataByModDir(dirName, origin);
  }

  /**
   * Provides the metadata for a given mod by its directory.
   *
   * @param dir The directory of the mod.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The mod metadata, or `null` if the mod does not exist.
   */
  public function getMetadataByModDir(dirName:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    var modPath:String = Util.pathJoin(modRoot, dirName);
    if (exists(modPath))
    {
      var meta:Null<ModMetadata> = null;

      var metaFile:String = Util.pathJoin(modPath, PolymodConfig.modMetadataFile);

      if (!exists(metaFile))
      {
        Polymod.warning(MOD_MISSING_METADATA, 'Could not find mod metadata file: $metaFile', origin);
        return null;
      }
      else
      {
        var metaText:Null<String> = getFileContent(metaFile);
        if (metaText == null || metaText == '')
        {
          Polymod.warning(MOD_MISSING_METADATA, 'Could not read mod metadata file for mod "$dirName"', origin);
          return null;
        }

        meta = ModMetadata.fromJsonStr(metaText, origin);
      }

      if (meta == null)
      {
        return null;
      }

      meta.id = meta.id == '' ? dirName : meta.id;
      meta.dirName = dirName;
      meta.modPath = modPath;

      var iconFile = getModIconPath(modPath, origin);
      var iconBytes:Null<Bytes> = getFileBytes(iconFile);
      if (iconBytes == null)
      {
        Polymod.warning(MOD_MISSING_ICON, 'Could not obtain mod icon data from file: $iconFile', origin);
      }
      else
      {
        meta.icon = iconBytes;
        meta.iconPath = iconFile;
      }

      return meta;
    }
    else
    {
      Polymod.error(MOD_MISSING_DIRECTORY, 'Could not find mod directory: $modPath', origin);
    }
    return null;
  }

  /**
   * Provides the metadata for a given mod by its ID.
   *
   * @param modId The ID of the mod.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The mod metadata, or `null` if the mod does not exist.
   */
  public function getMetadataByModId(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    var knownDirectory:Null<String> = scanModDirectoriesForId(modId, origin);
    if (knownDirectory != null)
    {
      var result:Null<ModMetadata> = getMetadataByModDir(knownDirectory, origin);
      if (result != null)
      {
        return result;
      }
      else
      {
        modMetadataLocations.remove(modId);
      }
    }

    // We don't know where the mod is located.
    return null;
  }

  /**
   * Get the metadata for a given mod.
   * This function is DEPRECATED, use `getMetadataByModId` for the same result.
   *
   * @param modId The ID of the mod as defined in the metadata.
   * @param origin The error reporting origin.
   * @return The mod metadata, or `null` if not found.
   */
  @:deprecated('This function is DEPRECATED, use `getMetadataByModId` for the same result.')
  public function getMetadataById(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return getMetadataByModId(modId, origin);
  }

  function hasMetadataFile(dirName:String):Bool
  {
    var modPath:String = Util.pathJoin(modRoot, dirName);
    if (!isDirectory(modPath)) return false;
    var metaFile:String = Util.pathJoin(modPath, PolymodConfig.modMetadataFile);
    return exists(metaFile);
  }
}
