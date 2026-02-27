package polymod.backends;

#if (!openfl || nme)
class OpenFLBackend extends StubBackend
{
  public function new()
  {
    super();
    Polymod.error(BACKEND_INIT_FAILED, "OpenFLBackend requires the openfl library, did you forget to install it?", INIT);
  }
}
#else
#if (!nme && !macro)
class OpenFLBackend extends LimeBackend
{
  public override function clearCache()
  {
    super.clearCache();

    clearBitmapCache();
    clearFontCache();
    clearSoundCache();
  }

  /**
   * These lines are needed until a PR merges:
   * https://github.com/openfl/openfl/pull/2534
   */
  static function clearBitmapCache():Void
  {
    // for (key in openfl.Assets.cache.getBitmapKeys())
    // {
    //   openfl.Assets.cache.removeBitmapData(key);
    // }
    var cache:openfl.utils.AssetCache = Std.isOfType(openfl.utils.Assets.cache, openfl.utils.AssetCache) ? cast openfl.utils.Assets.cache : null;
    if (cache == null) return; // Don't mess with custom asset cache implementations.
    for (key in cache.bitmapData.keys())
    {
      cache.bitmapData.remove(key);
    }
  }

  static function clearFontCache():Void
  {
    // for (key in openfl.Assets.cache.getFontKeys())
    // {
    //   openfl.Assets.cache.removeFont(key);
    // }
    var cache:openfl.utils.AssetCache = Std.isOfType(openfl.utils.Assets.cache, openfl.utils.AssetCache) ? cast openfl.utils.Assets.cache : null;
    if (cache == null) return; // Don't mess with custom asset cache implementations.
    for (key in cache.font.keys())
    {
      cache.font.remove(key);
    }
  }

  static function clearSoundCache():Void
  {
    // for (key in openfl.Assets.cache.getSoundKeys())
    // {
    //   openfl.Assets.cache.removeSound(key);
    // }
    var cache:openfl.utils.AssetCache = Std.isOfType(openfl.utils.Assets.cache, openfl.utils.AssetCache) ? cast openfl.utils.Assets.cache : null;
    if (cache == null) return; // Don't mess with custom asset cache implementations.
    for (key in cache.sound.keys())
    {
      cache.sound.remove(key);
    }
  }
}
#end
#end
