package polymod;

import openfl.media.Sound;
import haxe.io.Bytes;
import polymod.Polymod.Framework;
import polymod.Polymod.FrameworkParams;
import polymod.Polymod.PolymodErrorCode;
import polymod.backends.IBackend;
import polymod.backends.PolymodAssetLibrary;
import polymod.format.ParseRules;
import polymod.fs.PolymodFileSystem.IFileSystem;
import polymod.fs.StubFileSystem;
import polymod.fs.SysFileSystem;
#if firetongue
import firetongue.FireTongue;
#end

/**
 * Provides static utility functions for working with assets.
 * Note that you should also be able to just use your framework's asset retrieval functions,
 * and Polymod will inject its functionality in there.
 */
class PolymodAssets
{
  /**
   * Determine if a file with the given ID exists.
   * Queries both base assets and all loaded mods, with later mods taking priority.
   *
   * @param id The asset ID to query existance of.
   * @return Whether the asset exists.
   */
  public static function exists(id:String):Bool
  {
    return Polymod.assetLibrary.exists(id);
  }

  /**
   * Determine if a file with the given ID exists.
   * Queries only base assets, ignoring mods even if they are loaded.
   *
   * @param id The asset ID to query existance of.
   * @return Whether the asset exists.
   */
  public static function existsDirectly(id:String):Bool
  {
    return Polymod.assetLibrary.checkDirectly(id, '');
  }

  /**
   * Determine if a file with the given ID exists.
   * Queries directly from a given mod by ID.
   *
   * @param id The asset ID to query existance of.
   * @param modId The specific mod directory to fetch from.
   * @return Whether the asset exists.
   */
  public static function existsInMod(id:String, modId:String):Bool
  {
    return Polymod.assetLibrary.checkDirectly(id, modId);
  }

  /**
   * Attempt to load an asset synchronously, as byte data.
   * Fetches from both base assets and all loaded mods, with later mods taking priority.
   *
   * @param id The asset ID to query existance of.
   * @return The byte data for the file
   */
  public static function getBytes(id:String):Null<haxe.io.Bytes>
  {
    return Polymod.assetLibrary.getBytes(id);
  }

  /**
   * Attempts to load an asset synchronously, as byte data.
   * Fetches from base assets, ignoring mods even if they are loaded.
   *
   * @param id The asset ID to load.
   * @return The byte data for the file.
   */
  public static function getBytesDirectly(id:String):Null<haxe.io.Bytes>
  {
    return Polymod.assetLibrary.getBytesDirectly(id, '');
  }

  /**
   * Attempts to load an asset synchronously, as byte data.
   * Fetches directly from a given mod by ID.
   * NOTE: This can fetch modded assets, even if the mod ID is not loaded.
   *
   * @param id The asset ID to load.
   * @param modId The specific mod directory to fetch from.
   * @return The byte data for the file.
   */
  public static function getBytesFromMod(id:String, modId:String):Null<haxe.io.Bytes>
  {
    var modDir = Polymod.assetLibrary.getModDirectory(modId);
    return Polymod.assetLibrary.getBytesDirectly(id, modDir);
  }

  /**
   * Attempts to load an asset synchronously, as string text.
   * Fetches from both base assets and all loaded mods, with later mods taking priority.
   *
   * @param id The asset ID to load.
   * @return The string text for the file.
   */
  public static function getText(id:String):Null<String>
  {
    return Polymod.assetLibrary.getText(id);
  }

  /**
   * Attempts to load an asset synchronously, as string text.
   * Fetches from base assets, ignoring mods even if they are loaded.
   *
   * @param id The asset ID to load.
   * @return The string text for the file.
   */
  public static function getTextDirectly(id:String):Null<String>
  {
    return Polymod.assetLibrary.getTextDirectly(id, '');
  }

  /**
   * Attempts to load an asset synchronously, as string text.
   * Fetches directly from a given mod by ID.
   * NOTE: This can fetch modded assets, even if the mod ID is not loaded.
   *
   * @param id The asset ID to load.
   * @param modId The specific mod directory to fetch from.
   * @return The string text for the file.
   */
  public static function getTextFromMod(id:String, modId:String):Null<String>
  {
    var modDir = Polymod.assetLibrary.getModDirectory(modId);
    return Polymod.assetLibrary.getTextDirectly(id, modDir);
  }

  #if lime
  /**
   * Attempt to load an asset asynchronously, as byte data.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to query existance of.
   * @return The byte data for the file
   */
  public static function loadBytes(id:String):lime.app.Future<haxe.io.Bytes>
  {
    return Polymod.assetLibrary.loadBytes(id);
  }

  /**
   * Attempts to load an asset asynchronously, as string text.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to load.
   * @return A Future, which provides the string text for the file when asset loading completes.
   */
  public static function loadText(id:String):lime.app.Future<String>
  {
    return Polymod.assetLibrary.loadText(id);
  }

  #if openfl
  /**
   * Attempts to load an asset synchronously, as bitmap data.
   * Fetches from both base assets and all loaded mods, with later mods taking priority.
   *
   * @param id The asset ID to load.
   * @return The bitmap data for the file.
   */
  public static function getBitmapData(id:String):Null<openfl.display.BitmapData>
  {
    return Polymod.assetLibrary.getBitmapData(id);
  }

  /**
   * Attempts to load an asset synchronously, as bitmap data.
   * Fetches from base assets, ignoring mods even if they are loaded.
   *
   * @param id The asset ID to load.
   * @return The bitmap data for the file.
   */
  public static function getBitmapDataDirectly(id:String):Null<openfl.display.BitmapData>
  {
    return Polymod.assetLibrary.getBitmapDataDirectly(id, '');
  }

  /**
   * Attempts to load an asset synchronously, as bitmap data.
   * Fetches directly from a given mod by ID.
   * NOTE: This can fetch modded assets, even if the mod ID is not loaded.
   *
   * @param id The asset ID to load.
   * @param modId The specific mod directory to fetch from.
   * @return The bitmap data for the file.
   */
  public static function getBitmapDataFromMod(id:String, modId:String):Null<openfl.display.BitmapData>
  {
    var modDir = Polymod.assetLibrary.getModDirectory(modId);
    return Polymod.assetLibrary.getBitmapDataDirectly(id, modDir);
  }

  /**
   * Attempt to load an asset asynchronously, as bitmap data.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to query existance of.
   * @return A Future, which provides the bitmap data for the file when asset loading completes.
   */
  public static function loadBitmapData(id:String):lime.app.Future<openfl.display.BitmapData>
  {
    return Polymod.assetLibrary.loadBitmapData(id);
  }

  /**
   * Attempts to load an asset synchronously, as sound data.
   * Fetches from both base assets and all loaded mods, with later mods taking priority.
   *
   * @param id The asset ID to load.
   * @return The sound data for the file.
   */
  public static function getSound(id:String):Null<openfl.media.Sound>
  {
    return Polymod.assetLibrary.getSound(id);
  }

  /**
   * Attempts to load an asset synchronously, as sound data.
   * Fetches from base assets, ignoring mods even if they are loaded.
   *
   * @param id The asset ID to load.
   * @return The sound data for the file.
   */
  public static function getSoundDirectly(id:String):Null<openfl.media.Sound>
  {
    return Polymod.assetLibrary.getSoundDirectly(id, '');
  }

  /**
   * Attempts to load an asset synchronously, as sound data.
   * Fetches directly from a given mod by ID.
   * NOTE: This can fetch modded assets, even if the mod ID is not loaded.
   *
   * @param id The asset ID to load.
   * @param modId The specific mod directory to fetch from.
   * @return The sound data for the file.
   */
  public static function getSoundFromMod(id:String, modId:String):Null<openfl.media.Sound>
  {
    var modDir = Polymod.assetLibrary.getModDirectory(modId);
    return Polymod.assetLibrary.getSoundDirectly(id, modDir);
  }

  /**
   * Attempt to load an asset asynchronously, as sound data.
   * Fetches from both base assets and all loaded mods.
   *
   * @param id The asset ID to query existance of.
   * @return A Future, which provides the sound data for the file when asset loading completes.
   */
  public static function loadSound(id:String):lime.app.Future<openfl.media.Sound>
  {
    return Polymod.assetLibrary.loadSound(id);
  }
  #end

  #end

  /**
   * Get the absolute system file path for a given asset ID.
   * Queries both base assets and all loaded mods.
   *
   * @param id The asset ID to query.
   * @return The absolute file path to load for the asset.
   */
  public static function getPath(id:String):String
  {
    return Polymod.assetLibrary.getPath(id);
  }

  /**
   * Get a list of all asset IDs of the specified type.
   * Queries from both base assets and all loaded mods.
   *
   * @param type The asset type to filter by (optional).
   * @return An array of asset IDs.
   */
  public static function list(?type:PolymodAssetType):Array<String>
  {
    return Polymod.assetLibrary.list(type);
  }

  /**
   * Get a list of all asset IDs of the specified type.
   * Queries from base assets only, ignoring mods even if they are loaded.
   *
   * @param type The asset type to filter by (optional).
   * @return An array of asset IDs.
   */
  public static function listDirectly(?type:PolymodAssetType):Array<String>
  {
    return Polymod.assetLibrary.listDirectly('', type);
  }

  /**
   * Get a list of all asset IDs of the specified type in the specified mod.
   *
   * @param modId The mod ID to query.
   * @param type The asset type to filter by (optional).
   * @return An array of asset IDs.
   */
  public static function listInMod(modId:String, ?type:PolymodAssetType):Array<String>
  {
    return Polymod.assetLibrary.listDirectly(modId, type);
  }

  /**
   * Determine the correct framework to use based on the current environment.
   * Powered by compile-time macros.
   * @return The framework to use.
   */
  static function autoDetectFramework():Framework
  {
    #if castle
    return CASTLE;
    #end
    #if heaps
    return HEAPS;
    #end
    #if ceramic
    return CERAMIC;
    #end
    #if nme
    return NME;
    #end
    #if flixel
    return FLIXEL;
    #end
    #if (openfl && !nme)
    return OPENFL;
    #end
    #if (lime && !nme)
    return LIME;
    #end
    #if kha
    return KHA;
    #end
    return UNKNOWN;
  }
}

/**
 * An enumeration of asset types.
 */
enum abstract PolymodAssetType(String) from String to String
{
  /**
   * A file containing binary data.
   */
  public var BYTES = 'BYTES';

  /**
   * A file containing text data.
   */
  public var TEXT = 'TEXT';

  /**
   * A file containing a bitmap image.
   */
  public var IMAGE = 'IMAGE';

  /**
   * A file containing a video.
   */
  public var VIDEO = 'VIDEO';

  /**
   * A file containing font data.
   */
  public var FONT = 'FONT';

  /**
   * A file containing audio.
   */
  public var AUDIO_GENERIC = 'AUDIO_GENERIC';

  /**
   * A file containing music audio.
   */
  public var AUDIO_MUSIC = 'AUDIO_MUSIC';

  /**
   * A file containing sound audio.
   */
  public var AUDIO_SOUND = 'AUDIO_SOUND';

  /**
   * A file containing an asset manifest.
   */
  public var MANIFEST = 'MANIFEST';

  /**
   * A file containing an XML template.
   */
  public var TEMPLATE = 'TEMPLATE';

  /**
   * A file containing unidentified data.
   */
  public var UNKNOWN = 'UNKNOWN';

  /**
   * @param str A string representing an asset type.
   * @return The corresponding PolymodAssetType.
   */
  @:from
  public static function fromString(str:String):PolymodAssetType
  {
    str = str.toUpperCase();
    switch (str)
    {
      case BYTES, TEXT, IMAGE, VIDEO, FONT, AUDIO_GENERIC, AUDIO_MUSIC, AUDIO_SOUND, MANIFEST, TEMPLATE, UNKNOWN:
        return str;
      default:
        return UNKNOWN;
    }
    return UNKNOWN;
  }
}
