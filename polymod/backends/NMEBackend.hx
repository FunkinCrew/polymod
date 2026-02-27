package polymod.backends;

import haxe.xml.Fast;
import haxe.xml.Printer;
import polymod.Polymod;
import polymod.Polymod.FrameworkParams;
import polymod.Polymod.PolymodError;
import polymod.util.Util;
import polymod.backends.PolymodAssetLibrary;
import polymod.backends.PolymodAssets.PolymodAssetType;
#if unifill
import unifill.Unifill;
#end
import haxe.io.Bytes;
#if nme
import nme.Assets;
import nme.AssetType;
import nme.AssetInfo;
#end

#if !nme
class NMEBackend extends StubBackend
{
  public function new()
  {
    super();
    Polymod.error(BACKEND_INIT_FAILED, "NMEBackend requires the nme library, did you forget to install it?", INIT);
  }
}
#else
class NMEBackend implements IBackend
{
  // STATIC:
  // Instance:
  public var polymodLibrary:PolymodAssetLibrary;

  private var modAssets:Map<String, AssetInfo>;
  private var defaultAssets:Map<String, AssetInfo>;

  public function new() {}

  public function init(?params:FrameworkParams):Bool
  {
    restoreDefaultAssets();

    var list = polymodLibrary.listModFiles();
    modAssets = new Map<String, AssetInfo>();
    defaultAssets = new Map<String, AssetInfo>();

    for (file in list)
    {
      defaultAssets.set(file, nme.Assets.info.get(file));
      modAssets.set(file, new AssetInfo(polymodLibrary.file(file), PolyToNME(polymodLibrary.getType(file)), false, // ??
        null, null, null));
    }

    for (key in modAssets.keys())
    {
      nme.Assets.info.set(key, modAssets.get(key));
    }

    for (key in nme.Assets.info.keys())
    {
      var info = nme.Assets.info.get(key);
      if (info.type == TEXT)
      {
        if (info.isResource)
        {
          var origText = PolymodAssets.getText(key);
          var newText = polymodLibrary.mergeAndAppendText(key, origText);
          if (origText != newText)
          {
            var byteArray = nme.utils.ByteArray.fromBytes(Bytes.ofString(newText));
            info.setCache(byteArray, true);
            info.isResource = false;
          }
        }
        else
        {
          var modFile = polymodLibrary.file(key);
          nme.Assets.byteFactory.set(info.path, function() {
            var bytes = null;
            if (polymodLibrary.fileSystem.exists(modFile))
            {
              bytes = polymodLibrary.fileSystem.getFileBytes(modFile);
            }
            else
            {
              bytes = polymodLibrary.fileSystem.getFileBytes(key);
            }
            var origText = Std.string(bytes);
            var newText = polymodLibrary.mergeAndAppendText(key, origText);
            if (origText != newText)
            {
              return nme.utils.ByteArray.fromBytes(Bytes.ofString(newText));
            }
            return nme.utils.ByteArray.fromBytes(Bytes.ofString(origText));
          });
        }
      }
    }

    return true;
  }

  public function destroy()
  {
    restoreDefaultAssets();
    polymodLibrary = null;
    modAssets = null;
    defaultAssets = null;
  }

  private function restoreDefaultAssets()
  {
    if (modAssets == null) return;
    for (key in modAssets.keys())
    {
      var modAsset = modAssets.get(key);
      if (modAsset != null)
      {
        nme.Assets.info.remove(key);
      }
      var defaultAsset = defaultAssets.get(key);
      if (defaultAsset != null)
      {
        nme.Assets.info.set(key, defaultAsset);
      }
    }
  }

  private function PolyToNME(type:PolymodAssetType):AssetType
  {
    return switch (type)
    {
      case PolymodAssetType.BYTES: AssetType.BINARY;
      case PolymodAssetType.FONT: AssetType.FONT;
      case PolymodAssetType.IMAGE: AssetType.IMAGE;
      case PolymodAssetType.AUDIO_MUSIC: AssetType.MUSIC;
      case PolymodAssetType.AUDIO_SOUND: AssetType.SOUND;
      case PolymodAssetType.TEXT: AssetType.TEXT;
      // case PolymodAssetType.SWF : AssetType.SWF;
      // case PolymodAssetType.MOVIE_CLIP : AssetType.MOVIE_CLIP;
      default: AssetType.BINARY;
    }
  }

  public function exists(id:String):Bool
  {
    return Assets.exists(id);
  }

  public function getBytes(id:String):Bytes
  {
    return Assets.getBytes(id);
  }

  public function getText(id:String):String
  {
    return Assets.getText(id);
  }

  public function list(type:PolymodAssetType = null):Array<String>
  {
    throw 'Function not implemented';
  }

  public function getPath(id:String):String
  {
    throw 'Function not implemented';
  }

  public function clearCache()
  {
    for (key in Assets.info.keys())
    {
      var assetInfo = Assets.info.get(key);
      if (assetInfo != null && assetInfo.type == AssetType.IMAGE)
      {
        if (assetInfo.type == AssetType.IMAGE)
        {
          Assets.cache.removeBitmapData(assetInfo.path);
        }
        assetInfo.cache = null;
      }
    }
  }

  public function stripAssetsPrefix(id:String):String
  {
    if (Util.uIndexOf(id, 'assets/') == 0 || Util.uIndexOf(id, 'Assets/') == 0)
    {
      id = Util.uSubstring(id, 7);
    }
    return id;
  }
}
#end
