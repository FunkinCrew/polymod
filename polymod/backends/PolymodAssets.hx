package polymod.backends;

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

typedef PolymodAssetsParams =
{
  /**
   * the Haxe framework you're using (OpenFL, HEAPS, Kha, NME, etc..)
   */
  framework:polymod.Framework,

  /**
   * the file system to use to access mods.
   */
  fileSystem:IFileSystem,

  /**
   * (optional) any specific settings for your particular Framework
   */
  frameworkParams:FrameworkParams,

  /**
   * paths to each mod's root directories.
   * This takes precedence over the 'Dir' parameter and the order matters -- mod files will load from first to last, with last taking precedence
   */
  dirs:Array<String>,

  /**
   * (optional) parsing rules for various data formats
   */
  ?parseRules:ParseRules,
  /**
   * (optional) list of files it ignore in this mod asset library (get the fallback version instead)
   */
  ?ignoredFiles:Array<String>,
  /**
   * (optional) your own custom backend for handling assets
   */
  ?customBackend:Class<IBackend>,
  /**
   * (optional) maps file extensions to asset types. This ensures e.g. text files with unfamiliar extensions are handled properly.
   */
  ?extensionMap:Map<String, PolymodAssetType>,
  /**
   * (optional) if your assets folder is not named `assets/`, you can specify the proper name here
   * This prevents some bugs when calling `Assets.list()`, among other things.
   */
  ?assetPrefix:String,

  /**
   * (optional) a FireTongue instance for Polymod to hook into for localization support
   */
  #if firetongue
  ?firetongue:FireTongue,
  #end
  /**
   * (optional) whether to parse and allow for initialization of classes in script files
   */
  ?useScriptedClasses:Bool,
}

class PolymodAssets
{
  public static function init(params:PolymodAssetsParams):PolymodAssetLibrary
  {
    var framework:polymod.Framework = params.framework;
    if (framework == null)
    {
      framework = autoDetectFramework();
      Polymod.notice(PolymodErrorCode.FRAMEWORK_AUTODETECT, 'Framework: Autodetect, going with $framework');
    }
    else
    {
      Polymod.notice(PolymodErrorCode.FRAMEWORK_INIT, 'Framework: User specified $framework');
    }
    var backend:IBackend = null;
    #if !macro
    backend = switch (framework)
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
          Polymod.error(PolymodErrorCode.UNDEFINED_CUSTOM_BACKEND, "params.customBackend was not defined!");
          null;
        }
      default: null;
    }
    #end
    if (backend == null)
    {
      Polymod.error(PolymodErrorCode.FAILED_CREATE_BACKEND, 'Could not create a backend for framework: $framework');
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
        Polymod.error(PolymodErrorCode.FUNCTIONALITY_NOT_IMPLEMENTED,
          'Polymod currently does not support FireTongue localization for ${framework}! Nag us on GitHub about it.');
      }
    }
    #end

    if (library != null)
    {
      library.destroy();
    }

    library = new PolymodAssetLibrary(
      {
        backend: backend,
        dirs: params.dirs,
        parseRules: params.parseRules,
        ignoredFiles: params.ignoredFiles,
        extensionMap: params.extensionMap,
        fileSystem: params.fileSystem,
        assetPrefix: params.assetPrefix,
        frameworkParams: params.frameworkParams,
        #if firetongue
        firetongue: params.firetongue,
        #end
      });

    if (backend.init(params.frameworkParams))
    {
      // Initialization successful.
      return library;
    }
    else
    {
      return null;
    }
  }

  public static function exists(id:String):Bool
  {
    return library.exists(id);
  }

  public static function getBytes(id:String):Bytes
  {
    return library.getBytes(id);
  }

  public static function getText(id:String):String
  {
    return library.getText(id);
  }

  public static function getPath(id:String):String
  {
    return library.getPath(id);
  }

  public static function list(type:PolymodAssetType = null):Array<String>
  {
    return library.list(type);
  }

  private static var library:PolymodAssetLibrary;

  /**
   * Determine the correct framework to use based on the current environment.
   * Powered by compile-time macros.
   * @return polymod.Framework
   */
  private static function autoDetectFramework():polymod.Framework
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

enum abstract PolymodAssetType(String) from String to String
{
  var BYTES = 'BYTES';
  var TEXT = 'TEXT';
  var IMAGE = 'IMAGE';
  var VIDEO = 'VIDEO';
  var FONT = 'FONT';
  var AUDIO_GENERIC = 'AUDIO_GENERIC';
  var AUDIO_MUSIC = 'AUDIO_MUSIC';
  var AUDIO_SOUND = 'AUDIO_SOUND';
  var MANIFEST = 'MANIFEST';
  var TEMPLATE = 'TEMPLATE';
  var UNKNOWN = 'UNKNOWN';

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
