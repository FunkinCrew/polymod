package polymod.backends;

import haxe.io.Bytes;
import polymod.backends.IBackend;
import polymod.Polymod.Framework;
import polymod.PolymodAssets;
import polymod.PolymodAssets.PolymodAssetType;
import polymod.format.ParseRules;
import polymod.fs.PolymodFileSystem.IFileSystem;
import polymod.util.Util;
import polymod.Polymod.FrameworkParams;
#if firetongue
import firetongue.FireTongue;
#end
#if openfl
import openfl.text.Font;
#end

using StringTools;

/**
 * Initialized when Polymod mods are loaded, and handles retrieving assets from currently loading mods.
 */
@:allow(polymod.Polymod)
@:access(polymod.PolymodAssets)
class PolymodAssetLibrary
{
  public var backend(default, null):IBackend;
  public var fileSystem(default, null):IFileSystem;

  public var assetTypes(default, null):Map<String, PolymodAssetType>;
  public var typeLibraries(default, null):Map<String, Array<String>>;

  public var assetPrefix(default, null):String = "assets/";
  public var modIds:Array<String> = [];
  public var modDirs:Array<String> = [];
  public var ignoredFiles:Array<String> = [];

  var parseRules:ParseRules;
  var frameworkParams:FrameworkParams;
  var extensions:Map<String, PolymodAssetType>;

  // Cache for directory listings to avoid repeated file system scans
  var dirCache:Map<String, Array<String>> = [];
  // Fast lookup for ignored files using Map instead of array searches
  var ignoredFilesCache:Map<String, Bool> = [];
  // Cache for file existence checks
  var fileExistsCache:Map<String, Bool> = [];
  // Cache for asset types to avoid repeated extension parsing
  var assetTypeCache:Map<String, PolymodAssetType> = [];
  // Pre-built list of all available files across all mods
  var allFilesCache:Null<Array<String>> = null;
  // Cache for processed text files
  var textCache:Map<String, String> = [];

  #if firetongue
  private var tongue:FireTongue = null;

  /**
   * The directory where all the FireTongue locales are stored.
   */
  public var rawTongueDirectory(default, null):String = null;

  /**
   * The directory where the current locale's FireTongue files are stored.
   */
  public var localePrefix(default, null):String = null;

  /**
   * The directory where the current locale's FireTongue localized assets are stored.
   *
   * Prefix asset paths with this string to get a localized version of the asset.
   */
  public var localeAssetPrefix(default, null):String = null;
  #end

  // Private constructor, use PolymodAssetLibrary.build() instead!
  function new(backend:IBackend, fileSystem:IFileSystem,
    modIds:Array<String>, modDirs:Array<String>,
    parseRules:ParseRules,
    frameworkParams:FrameworkParams,
    ignoredFiles:Array<String>,
    extensionMap:Map<String, PolymodAssetType>,
    assetPrefix:String = 'assets/',

    #if firetongue
    ?firetongue:FireTongue,
    #end
    )
  {
    this.backend = backend;

    this.fileSystem = fileSystem;
    this.modIds = modIds;
    this.modDirs = modDirs;
    this.parseRules = parseRules;
    this.frameworkParams = frameworkParams;
    this.ignoredFiles = ignoredFiles.copy();
    this.extensions = extensionMap;
    this.assetPrefix = assetPrefix;

    #if firetongue
    tongue = firetongue;
    if (tongue != null)
    {
      // Call when we build the asset library then again each time we change locale.
      onFireTongueLoad();
      tongue.addFinishedCallback(onFireTongueLoad);
    }
    #end

    backend.clearCache();
    init();

    buildAllFilesCache();
  }

  /**
   * Construct a PolymodAssetLibrary based on the given parameters.
   *
   * @param params The parameters to use.
   * @return The initialized PolymodAssetLibrary instance, or `null` if initialization failed.
   */
  public static function build(params:PolymodAssetLibraryParams):Null<PolymodAssetLibrary>
  {
    var framework:polymod.Framework = params.framework;
    if (framework == null)
    {
      framework = polymod.PolymodAssets.autoDetectFramework();
      Polymod.info(FRAMEWORK_INIT, 'Framework: Autodetect, going with $framework');
    }
    else
    {
      Polymod.info(FRAMEWORK_INIT, 'Framework: User specified $framework');
    }
    var backendToUse:Null<IBackend> = null;
    #if !macro
    backendToUse = switch (framework)
    {
      case CASTLE: new polymod.backends.CastleBackend();
      case NME: new polymod.backends.NMEBackend();
      case FLIXEL: new polymod.backends.FlixelBackend();
      case OPENFL: new polymod.backends.OpenFLBackend();
      case OPENFL_WITH_NODE: new polymod.backends.OpenFLWithNodeBackend();
      case LIME: new polymod.backends.LimeBackend();
      case HEAPS: new polymod.backends.HEAPSBackend();
      case KHA: new polymod.backends.KhaBackend();
      case CERAMIC: new polymod.backends.CeramicBackend();
      case CUSTOM:
        if (params.customBackend != null)
        {
          Type.createInstance(params.customBackend, []);
        }
        else
        {
          Polymod.error(BACKEND_CUSTOM_UNDEFINED, 'customBackend was not defined!', INIT);
          null;
        }
      default: null;
    }
    #end
    if (backendToUse == null)
    {
      Polymod.error(BACKEND_INIT_FAILED, 'Could not initialize backend for framework: $framework', INIT);
      return null;
    }

    #if firetongue
    if (params.firetongue != null)
    {
      if (framework == polymod.Framework.NME
        || framework == polymod.Framework.HEAPS
        || framework == polymod.Framework.KHA
        || framework == polymod.Framework.CERAMIC
        || framework == polymod.Framework.CASTLE)
      {
        Polymod.error(POLYMOD_FUNCTIONALITY_NOT_IMPLEMENTED,
          'Polymod currently does not support FireTongue localization for ${framework}! Nag us on GitHub about it.', INIT);
      }
    }
    #end

    if (backendToUse.polymodLibrary != null)
    {
      backendToUse.polymodLibrary.destroy();
    }

    backendToUse.polymodLibrary = new PolymodAssetLibrary(
      backendToUse,
      params.fileSystem,
      params.modIds,
      params.modDirs,
      params.parseRules,
      params.frameworkParams,
      params.ignoredFiles,
      params.extensionMap,
      params.assetPrefix,

      #if firetongue
      params.firetongue,
      #end
    );

    if (backendToUse.init(params.frameworkParams))
    {
      // Initialization successful.
      return backendToUse.polymodLibrary;
    }
    else
    {
      return null;
    }
  }

  #if firetongue
  /**
   * Do basic initialization based on the FireTongue instance
   * Must be redone if the locale changes
   */
  function onFireTongueLoad()
  {
    if (tongue == null) return;

    rawTongueDirectory = tongue.directory;
    localePrefix = Util.pathJoin(rawTongueDirectory, tongue.locale);
    localeAssetPrefix = Util.pathJoin(localePrefix, assetPrefix);

    // Clear caches when locale changes
    clearCaches();
  }
  #end

  function clearCaches():Void
  {
    dirCache = [];
    ignoredFilesCache = [];
    fileExistsCache = [];
    assetTypeCache = [];
    allFilesCache = null;
    textCache = [];
  }

  /**
   * For the given base text, apply any merge and append operations provided by mods.
   * For example, `json` files may have JSONPatch files to apply.
   *
   * @param id The asset ID for the text.
   * @param modText The base value of the text.
   * @return The merged and appended text.
   */
  public function mergeAndAppendText(id:String, modText:String):String
  {
    var cacheKey = PolymodConfig.mergeFolder + id;
    if (PolymodConfig.enableTextCache && textCache.exists(cacheKey))
    {
      return textCache.get(cacheKey);
    }

    modText = Util.mergeAndAppendText(modText, id, modIds, getTextDirectly, fileSystem, parseRules);

    if (PolymodConfig.enableTextCache)
    {
      textCache.set(cacheKey, modText);
    }

    return modText;
  }

  /**
   * Determine the PolymodAssetType based on the provided extension map.
   * This can include default extension mappings as well as ones provided by the game.
   *
   * @param ext The extension to check.
   * @return The matching `PolymodAssetType`, or `UNKNOWN` if the asset type isn't found.
   */
  public function getAssetType(ext:String):PolymodAssetType
  {
    ext = ext.toLowerCase();

    if (assetTypeCache.exists(ext))
    {
      return assetTypeCache.get(ext);
    }

    var result:PolymodAssetType = BYTES;
    if (extensions != null && extensions.exists(ext))
    {
      result = extensions.get(ext);
    }

    assetTypeCache.set(ext, result);
    return result;
  }

  /**
   * Fetch bytes directly from the file system.
   * Ignores any modded asset replacements, but ignores merging and appending.
   *
   * @param id The asset ID of the file.
   * @param modId A specific mod ID to fetch from.
   * @return The bytes of the modded asset, or `null` if the asset couldn't be fetched.
   */
  public function getBytesDirectly(id:String, modId:String = ''):Null<haxe.io.Bytes>
  {
    if (modId != '')
    {
      if (checkDirectly(id, modId))
      {
        var idStripped = stripAssetsPrefix(id);
        return fileSystem.getFileBytesByModId(idStripped, modId);
      }
      else
      {
        return null;
      }
    }
    else
    {
      return fileSystem.getFileBytes(id);
    }
  }

  /**
   * Fetch text directly from the file system.
   * Queries for any modded asset replacements, but ignores merging and appending.
   *
   * @param id The asset ID of the file.
   * @param modId A specific mod to fetch from.
   * @return The text of the modded asset, or `null` if the asset couldn't be fetched.
   */
  public function getTextDirectly(id:String, modId:String):Null<String>
  {
    var bytes:Null<haxe.io.Bytes> = getBytesDirectly(id, modId);

    return (bytes == null) ? null : bytes.getString(0, bytes.length);
  }

  #if openfl
  /**
   * Fetch text directly from the file system.
   * Queries for any modded asset replacements, but ignores merging and appending.
   *
   * @param id The asset ID of the file.
   * @param modId A specific mod to fetch from.
   * @return The text of the modded asset, or `null` if the asset couldn't be fetched.
   */
  public function getBitmapDataDirectly(id:String, modId:String):Null<openfl.display.BitmapData>
  {
    var bytes:Null<haxe.io.Bytes> = getBytesDirectly(id, modId);

    return (bytes == null) ? null : openflBitmapDataFromBytes(bytes);
  }

  function openflBitmapDataFromBytes(bytes:haxe.io.Bytes):openfl.display.BitmapData
  {
    var image = lime.graphics.Image.fromBytes(bytes);
    var bitmapData = openfl.display.BitmapData.fromImage(image);
    return bitmapData;
  }

  /**
   * Fetch text directly from the file system.
   * Queries for any modded asset replacements, but ignores merging and appending.
   *
   * @param id The asset ID of the file.
   * @param modId A specific mod to fetch from.
   * @return The text of the modded asset, or `null` if the asset couldn't be fetched.
   */
  public function getSoundDirectly(id:String, modId:String):Null<openfl.media.Sound>
  {
    var bytes:Null<haxe.io.Bytes> = getBytesDirectly(id, modId);

    return (bytes == null) ? null : openflSoundFromBytes(bytes);
  }

  function openflSoundFromBytes(bytes:haxe.io.Bytes):openfl.media.Sound
  {
    var audioBuffer = lime.media.AudioBuffer.fromBytes(bytes);
    var sound = openfl.media.Sound.fromAudioBuffer(audioBuffer);
    return sound;
  }
  #end

  /**
   * Determine if a file with the given ID exists.
   * Queries both base assets and all loaded mods.
   *
   * @param id The asset ID to query existance of.
   * @return Whether the asset exists.
   */
  public function exists(id:String):Bool
  {
    return backend.exists(id);
  }

  /**
   * Get the mod directory based on the mod ID.
   *
   * @param modId The ID of the mod to look for.
   * @return The directory path where the mod was found, or `null` if not found.
   */
  public function getModDirectory(modId:String):Null<String>
  {
    return fileSystem.scanModDirectoriesForId(modId);
  }

  /**
   * Attempts to load an asset synchronously, as string text.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to load.
   * @return The string text for the file.
   */
  public function getText(id:String):String
  {
    if (PolymodConfig.enableTextCache && textCache.exists(id))
    {
      return textCache.get(id);
    }

    var result = backend.getText(id);

    if (PolymodConfig.enableTextCache && result != null)
    {
      textCache.set(id, result);
    }

    return result;
  }

  /**
   * Attempt to load an asset synchronously, as byte data.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to query existance of.
   * @return The byte data for the file
   */
  public function getBytes(id:String):Bytes
  {
    return backend.getBytes(id);
  }

  #if lime
  /**
   * Attempt to load an asset asynchronously, as byte data.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to query existance of.
   * @return The byte data for the file
   */
  public function loadBytes(id:String):lime.app.Future<Bytes>
  {
    return backend.loadBytes(id);
  }

  /**
   * Attempts to load an asset asynchronously, as string text.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to load.
   * @return A Future, which provides the string text for the file when asset loading completes.
   */
  public function loadText(id:String):lime.app.Future<String>
  {
    return backend.loadText(id);
  }

  #if openfl
  /**
   * Attempts to load an asset synchronously, as bitmap data.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to load.
   * @return The bitmap data for the file.
   */
  public function getBitmapData(id:String):openfl.display.BitmapData
  {
    return backend.getBitmapData(id);
  }

  /**
   * Attempts to load an asset asynchronously, as bitmap data.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to load.
   * @return A Future, which provides the bitmap data for the file when asset loading completes.
   */
  public function loadBitmapData(id:String):lime.app.Future<openfl.display.BitmapData>
  {
    return backend.loadBitmapData(id);
  }

  /**
   * Attempts to load an asset synchronously, as bitmap data.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to load.
   * @return The bitmap data for the file.
   */
  public function getSound(id:String):openfl.media.Sound
  {
    return backend.getSound(id);
  }

  /**
   * Attempts to load an asset asynchronously, as bitmap data.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to load.
   * @return A Future, which provides the bitmap data for the file when asset loading completes.
   */
  public function loadSound(id:String):lime.app.Future<openfl.media.Sound>
  {
    return backend.loadSound(id);
  }
  #end

  /**
   * @return A list of asset libraries for this framework.
   */
  public function listLibraries():Array<String>
  {
    return backend.listLibraries();
  }
  #end

  /**
   * Get the absolute system file path for a given asset ID.
   * Queries both base assets and all loaded mods.
   *
   * @param id The asset ID to query.
   * @return The absolute file path to load for the asset.
   */
  public function getPath(id:String):String
  {
    return backend.getPath(id);
  }

  /**
   * Clear any internal path caches made by this asset library.
   */
  public function clearCache():Void
  {
    backend.clearCache();
    clearCaches();
  }

  /**
   * Get a list of all asset IDs of the specified type.
   * Queries from both base assets and all loaded mods.
   *
   * @param type The asset type to filter by (optional).
   * @return An array of asset IDs.
   */
  public function list(?type:PolymodAssetType):Array<String>
  {
    // Use pre-built cache when possible
    if (type == null && allFilesCache != null)
    {
      return allFilesCache.copy();
    }

    return backend.list(type);
  }

  public function listDirectly(modId:String, ?type:PolymodAssetType):Array<String>
  {
    var result:Array<String> = [];

    if (modId == '')
    {
      result = fileSystem.readDirectoryRecursive(assetPrefix);
    }
    else
    {
      var modDir = fileSystem.scanModDirectoriesForId(modId);
      if (modDir != null)
      {
        result = fileSystem.readModDirectory(modDir, true);
      }
    }

    // Filter
    return result.filter((id) -> {
      if (isAssetExcluded(id)) return false;

      if (type == null) return true;

      var assetType = getAssetType(haxe.io.Path.extension(id));
      if (assetType != type) return false;
      return true;
    });
  }

  public function listModFiles(?type:PolymodAssetType):Array<String>
  {
    // Use pre-built cache
    if (allFilesCache != null)
    {
      if (type == null)
      {
        return allFilesCache.copy();
      }

      var filtered:Array<String> = [];
      for (id in allFilesCache)
      {
        if (check(id, type))
        {
          filtered.push(id);
        }
      }
      return filtered;
    }

    var items = [];
    for (id in this.assetTypes.keys())
    {
      if (items.indexOf(id) != -1) continue;
      if (Util.isMergeOrAppend(id)) continue;
      if (type == null || type == BYTES || check(id, type))
      {
        items.push(id);
      }
    }
    return items;
  }

  /**
   * Check if the given asset of the given type exists in the file system.
   * Queries only loaded mods and excludes base game assets. For some reason.
   * (If using multiple mods, it will return true if ANY of the mod folders contains this file)
   *
   * @param id The asset ID to check.
   * @param type An asset type to filter by (optional).
   * @return Whether the given asset of the given type exists in the file system.
   */
  public function check(id:String, ?type:PolymodAssetType):Bool
  {
    var exists = checkExists(id);
    if (exists && type != null && type != PolymodAssetType.BYTES)
    {
      var otherType = this.assetTypes.get(id);
      exists = (otherType == type || otherType == PolymodAssetType.BYTES || otherType == null || otherType == '');
    }
    return exists;
  }

  /**
   * Get the asset type of the asset with the given ID.
   *
   * @param id The asset ID to check.
   * @return The asset type, or `UNKNOWN` if the file couldn't be located.
   */
  public function getType(id:String):PolymodAssetType
  {
    var exists = checkExists(id);
    if (exists)
    {
      return this.assetTypes.get(id);
    }
    return UNKNOWN;
  }

  /**
   * Check the file system directly for an asset of the given ID.
   *
   * @param id The ID to check.
   * @param modId The mod ID to check in.
   * @return Whether the asset exists.
   */
  public function checkDirectly(id:String, modId:String = ''):Bool
  {
    var idStripped = stripAssetsPrefix(id);
    if (modId == null || modId == '')
    {
      return cachedFileSystemExists(idStripped);
    }
    else
    {
      return fileSystem.existsByModId(idStripped, modId);
    }
  }

  /**
   * Get the absolute file path of the given asset id.
   * Queries both base assets and all loaded mods.
   *
   * @param id The ID of the asset to query.
   * @param modDir A mod directory to fetch from directly. (optional)
   * @return The asset's absolute file path.
   */
  public function file(id:String, modDir:String = ''):String
  {
    var idStripped = stripAssetsPrefix(id);
    if (modDir != '')
    {
      if (idStripped.startsWith(modDir)) return idStripped;
      return Util.pathJoin(modDir, idStripped);
    }

    var result = '';
    var resultLocalized = false;
    for (modDir in modDirs)
    {
      #if firetongue
      if (localeAssetPrefix != null)
      {
        var localePath = Util.pathJoin(modDir, Util.pathJoin(localeAssetPrefix, idStripped));
        if (cachedFileSystemExists(localePath))
        {
          result = localePath;
          resultLocalized = true;
        }
      }
      // Else, FireTongue not enabled.
      #end

      if (resultLocalized) continue;

      if (!resultLocalized)
      {
        // If we have an asset prefix

        var filePath = Util.pathJoin(modDir, idStripped);
        if (cachedFileSystemExists(filePath)) result = filePath;
      }
    }
    return result;
  }

  /**
   * Get the filename of the given asset id, with the given locale prefix prepended.
   * This ignores installed mods.
   *
   * @param id The asset ID.
   * @return The localized filename path, or `null` if FireTongue localization is not enabled.
   */
  public function fileLocale(id:String):Null<String>
  {
    #if firetongue
    if (localeAssetPrefix != null)
    {
      var idStripped = stripAssetsPrefix(id);
      return Util.pathJoin(localeAssetPrefix, idStripped);
    }
    // Else, Firetongue is not enabled.
    #end
    // Else, Firetongue is not installed.
    return null;
  }

  function cachedFileSystemExists(path:String):Bool
  {
    if (fileExistsCache.exists(path))
    {
      return fileExistsCache.get(path);
    }

    var exists = fileSystem.exists(path);
    fileExistsCache.set(path, exists);
    return exists;
  }

  function checkExists(id:String):Bool
  {
    if (isAssetExcluded(id)) return false;

    id = stripAssetsPrefix(id);
    for (modDir in modDirs)
    {
      #if firetongue
      if (localeAssetPrefix != null)
      {
        var localePath = Util.pathJoin(modDir, Util.pathJoin(localeAssetPrefix, id));
        if (cachedFileSystemExists(localePath)) return true;
      }
      // Else, FireTongue not enabled.
      #end

      var filePath = Util.pathJoin(modDir, id);
      if (cachedFileSystemExists(filePath))
      {
        return true;
      }
    }
    // The loop didn't find it.
    return false;
  }

  function init():Void
  {
    assetTypes = [];
    typeLibraries = ['default' => []];

    // Load libraries from frameworkParams.
    if (frameworkParams != null && frameworkParams.assetLibraryPaths != null)
    {
      for (k in frameworkParams.assetLibraryPaths.keys())
      {
        if (!typeLibraries.exists(k)) typeLibraries.set(k, []);
      }
    }

    initExtensions();
    if (parseRules == null) parseRules = ParseRules.getDefault();
    if (modDirs != null)
    {
      for (modDir in modDirs)
      {
        initMod(modDir);
      }
    }
  }

  function buildAllFilesCache():Void
  {
    allFilesCache = [];
    for (id in assetTypes.keys())
    {
      if (Util.isMergeOrAppend(id)) continue;
      allFilesCache.push(id);
    }
  }

  function initExtensions():Void
  {
    if (extensions == null) extensions = new Map<String, PolymodAssetType>();

    extensionSet('mp3', AUDIO_SOUND);
    extensionSet('ogg', AUDIO_SOUND);
    extensionSet('wav', AUDIO_SOUND);

    extensionSet('otf', FONT);
    extensionSet('ttf', FONT);

    extensionSet('bmp', IMAGE);
    extensionSet('gif', IMAGE);
    extensionSet('jpg', IMAGE);
    extensionSet('png', IMAGE);
    extensionSet('tga', IMAGE);
    extensionSet('tif', IMAGE);
    extensionSet('tiff', IMAGE);

    extensionSet('csv', TEXT);
    extensionSet('hx', TEXT);
    extensionSet('hxc', TEXT);
    extensionSet('hxs', TEXT);
    extensionSet('json', TEXT);
    extensionSet('md', TEXT);
    extensionSet('mpf', TEXT);
    extensionSet('tmx', TEXT);
    extensionSet('tsv', TEXT);
    extensionSet('tsx', TEXT);
    extensionSet('txt', TEXT);
    extensionSet('vdf', TEXT);
    extensionSet('xml', TEXT);

    extensionSet('avi', VIDEO);
    extensionSet('mkv', VIDEO);
    extensionSet('mov', VIDEO);
    extensionSet('mp4', VIDEO);
    extensionSet('webm', VIDEO);
  }

  function extensionSet(str:String, type:PolymodAssetType):Void
  {
    if (!extensions.exists(str))
    {
      extensions.set(str, type);
    }
  }

  function initMod(modDir:String):Void
  {
    if (modDir == null) return;
    Polymod.info(MOD_LOAD_START, 'Preparing to load mod $modDir');

    var all:Array<String> = null;

    if (dirCache.exists(modDir))
    {
      all = dirCache.get(modDir);
    }
    else
    {
      try
      {
        if (cachedFileSystemExists(modDir))
        {
          all = fileSystem.readDirectoryRecursive(modDir);
          dirCache.set(modDir, all);
        }
      }
      catch (msg:Dynamic)
      {
        Polymod.error(MOD_LOAD_FAILED, 'Failed to load mod $modDir : $msg', INIT);
        throw('ModAssetLibrary._initMod("$modDir") failed: $msg');
      }
    }

    all ??= [];

    for (file in all)
    {
      var doti = Util.uLastIndexOf(file, '.');
      var ext:String = doti != -1 ? file.substring(doti + 1) : '';
      ext = ext.toLowerCase();
      var assetType = getAssetType(ext);
      assetTypes.set(file, assetType);

      var kruePath:String = file;
      for (folder in [PolymodConfig.mergeFolder, PolymodConfig.appendFolder])
      {
        if (Util.uIndexOf(file, '$folder/') == 0)
        {
          kruePath = Util.uSubstring(file, folder.length + 1);
          break;
        }
      }
      var libi = Util.uIndexOf(kruePath, '/');
      var lib:String = libi != -1 ? Util.uSubstring(kruePath, 0, libi) : '';
      if (lib != '')
      {
        var added = false;
        if (frameworkParams != null && frameworkParams.assetLibraryPaths != null)
        {
          for (k in frameworkParams.assetLibraryPaths.keys())
          {
            var v = frameworkParams.assetLibraryPaths.get(k);
            if (v == lib)
            {
              if (!typeLibraries.exists(k)) typeLibraries.set(k, []);
              typeLibraries.get(k).push(file);
              added = true;
              break;
            }
          }
        }
        if (!added) typeLibraries.get('default').push(file);
      }
      else
      {
        typeLibraries.get('default').push(file);
      }

      #if openfl
      if (assetType == FONT)
      {
        var font = Font.fromFile(this.file(file, modDir));

        if (font == null)
        {
          font = Font.fromBytes(fileSystem.getFileBytesByModId(file, modDir));
        }

        if (font != null)
        {
          // Check if font is already registered before registering
          @:privateAccess
          if (!Font.__fontByName.exists(font.fontName))
          {
            Font.registerFont(font);
          }
        }
      }
      #end
    }
    Polymod.info(MOD_LOAD_DONE, 'Done loading mod $modDir');
  }

  @:allow(polymod.backends.LimeCoreLibrary)
  function initRedirectPath(libraryId:String, redirectPath:String, pathPrefix:String = ''):Void
  {
    if (!typeLibraries.exists(libraryId))
    {
      typeLibraries.set(libraryId, []);
    }

    if (redirectPath == null || redirectPath == '') return;

    redirectPath = Util.pathJoin(redirectPath, pathPrefix);

    var all:Array<String> = [];

    try
    {
      if (cachedFileSystemExists(redirectPath))
      {
        all = fileSystem.readDirectoryRecursive(redirectPath);
      }
      else
      {
        Polymod.error(ASSET_REDIRECT_MISSING_DIRECTORY, 'Failed to load core asset redirect $redirectPath : Directory does not exist!', INIT);
        throw('ModAssetLibrary.initRedirectPath("$redirectPath") failed: Directory does not exist!');
      }
    }
    catch (msg:Dynamic)
    {
      Polymod.error(ASSET_REDIRECT_FAILED, 'Failed to load core asset redirect $redirectPath : $msg', INIT);
      throw('ModAssetLibrary.initRedirectPath("$redirectPath") failed: $msg');
    }

    for (f in all)
    {
      var doti = Util.uLastIndexOf(f, '.');
      var ext:String = doti != -1 ? f.substring(doti + 1) : '';
      ext = ext.toLowerCase();
      var assetType = getAssetType(ext);
      assetTypes.set(f, assetType);
      if (!typeLibraries.exists(libraryId)) typeLibraries.set(libraryId, []);
      typeLibraries.get(libraryId).push(f);
      #if openfl
      if (assetType == FONT)
      {
        var font = Font.fromFile(file(f, redirectPath));

        if (font == null)
        {
          font = Font.fromBytes(fileSystem.getFileBytes(file(f, redirectPath)));
        }

        if (font != null)
        {
          // Check if font is already registered before registering
          @:privateAccess
          if (!Font.__fontByName.exists(font.fontName))
          {
            Font.registerFont(font);
          }
        }
      }
      #end
    }
    var keyCount = typeLibraries.get(libraryId).length;
    Polymod.info(ASSET_REDIRECT_DONE, 'Done loading core asset redirect $redirectPath ($keyCount keys)', INIT);

    buildAllFilesCache();
  }

  /**
   * Strip the `assets/` prefix from a file path, if it is present.
   * If your app uses a different asset path prefix, you can override this with the `assetPrefix` parameter.
   *
   * @param id The path to strip.
   * @return The modified path
   */
  public function stripAssetsPrefix(id:String):String
  {
    if (Util.uIndexOf(id, assetPrefix) == 0)
    {
      id = Util.uSubstring(id, assetPrefix.length);
    }
    return id;
  }

  /**
   * Add the `assets/` prefix to a file path, if it isn't present.
   * If your app uses a different asset path prefix, you can override this with the `assetPrefix` parameter.
   *
   * @param id The path to prepend
   * @return The modified path
   */
  public function prependAssetsPrefix(id:String):String
  {
    if (Util.uIndexOf(id, assetPrefix) == 0)
    {
      return id;
    }
    return '$assetPrefix$id';
  }

  public function isAssetExcluded(id:String):Bool
  {
    if (ignoredFiles.length == 0) return false;
    if (ignoredFilesCache.exists(id)) return ignoredFilesCache.get(id);

    var idStripped = stripAssetsPrefix(id);
    var idPrepend = prependAssetsPrefix(idStripped);

    for (pattern in ignoredFiles)
    {
      if (Util.uIndexOf(idStripped, pattern) == 0 || Util.uIndexOf(idPrepend, pattern) == 0)
      {
        ignoredFilesCache.set(id, true);
        return true;
      }
    }

    ignoredFilesCache.set(id, false);
    return false;
  }

  public function destroy():Void
  {
    backend?.destroy();
    clearCaches();
    Polymod.clearScripts();
  }
}


typedef PolymodAssetLibraryParams =
{
  /**
   * the Haxe framework you're using (OpenFL, HEAPS, Kha, NME, etc..)
   */
  framework:Framework,

  /**
   * the file system to use to access mod assets from storage
   */
  fileSystem:IFileSystem,

  /**
   * (optional) any specific settings for your particular Framework
   */
  ?frameworkParams:FrameworkParams,

  /**
   * (optional) your own custom backend for handling assets
   */
  ?customBackend:Class<IBackend>,

  /**
   * IDs of the mods to load.
   * order matters -- mod files will load from first to last, with last taking precedence
   */
  modIds:Array<String>,

  /**
   * paths to each mod's root directories.
   * order matters -- mods will load from first to last, with last taking precedence
   */
  modDirs:Array<String>,

  /**
   * (optional) formatting rules for parsing various data formats
   */
  ?parseRules:ParseRules,

  /**
   * (optional) list of files it ignore in this mod asset library (get the fallback version instead)
   */
  ?ignoredFiles:Array<String>,

  /**
   * (optional) maps file extensions to asset types. This ensures e.g. text files with unfamiliar extensions are handled properly.
   */
  ?extensionMap:Map<String, PolymodAssetType>,

  /**
   * (optional) if your assets folder is not named `assets/`, you can specify the proper name here
   * This prevents some bugs when calling `Assets.list()`, among other things.
   */
  ?assetPrefix:String,

  #if firetongue
  /**
   * (optional) a FireTongue instance for Polymod to hook into for localization support
   */
  ?firetongue:FireTongue,
  #end

  /**
   * (optional) whether to parse and allow for initialization of classes in script files
   */
  ?useScriptedClasses:Bool,
}
