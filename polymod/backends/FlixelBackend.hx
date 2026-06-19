package polymod.backends;

#if flixel
#if !macro
import lime.utils.Assets as LimeAssets;
import openfl.Assets as OpenFLAssets;
#end
import openfl.utils.AssetType;
#end

#if (!flixel)
class FlixelBackend extends StubBackend
{
  public function new()
  {
    super();
    Polymod.error(BACKEND_INIT_FAILED, "FlixelBackend requires the flixel library, did you forget to install it?", INIT);
  }
}
#else
#if !macro
class FlixelBackend extends OpenFLBackend
{
  public function new()
  {
    super();
    Polymod.debug('Initialized Flixel backend.');
  }

  /**
   * Special handling to ensure Flixel's aggressive Bitmap caches get cleared.
   * NOTE: You may need to manually remove certain images from the cache, if you created them based on an asset
   *   (such as with `FlxGraphic.fromFrame`)
   */
  public override function clearCache()
  {
    Polymod.info(POLYMOD_FUNCTIONALITY_NOT_IMPLEMENTED,
      "Watch out, the Flixel backend's clearCache function kinda sucks. " + "Ideally you should just disable Flixel's caching and manage everything yourself.");
    // To clarify, Flixel caches things in a way that is hard to clear automatically.
    // The FlxG.bitmap cache contains the following:
    // - Graphics loaded using FlxSprite.loadGraphic
    //     We need to clear these, and Flixel will safely reload them when needed, appropriately loading modded content.
    // - Graphics created wholesale using FlxSprite.makeGraphic or FlxText
    //     We can't clear these, though mods don't override them so we're fine here.
    // - Graphics created from calling FlxGraphic.fromFrame on another graphic
    //     We can't clear these, but the graphic they come from may be modded.
    //     If you happen to be using this and you load or unload mods, it might leave old content behind.

    // Try the following if you're having problems with this:
    // - Set the `Cache` argument to false on any calls to `loadGraphic` and manage/clear the cache yourself.
    // - Avoid use of functions that might create a new graphic based on one loaded from an asset.
    //     TODO: Does FlxAtlasFrames do this?
    // - Require the user to restart the application after modding.
    //     You can invoke a system process to launch the game's own executable, then exit.

    // The workaround used here is to fetch the list of all bitmaps, and attempt to clear each.

    var bitmapsToClear = OpenFLAssets.list(AssetType.IMAGE);
    Polymod.debug('Known image keys: ${bitmapsToClear.length}');
    var count = 0;
    for (key in bitmapsToClear)
    {
      #if !macro
      flixel.FlxG.bitmap.removeByKey(key);
      #end
      openfl.Assets.cache.removeBitmapData(key);
    }
    Polymod.debug('Cleared $count items from Flixel bitmap cache.');

    // Sounds and fonts will be cleared by the superclass.
    super.clearCache();
  }

  /**
   * Gets called when the backend is being destroyed.
   * This happens when `Polymod.init()` is called again, which means mods are being reloaded.
   */
  public override function destroy()
  {
    // Make sure the cache gets cleared while we still know the list of assets.
    clearCache();
    super.destroy();
  }
}
#end
#end
