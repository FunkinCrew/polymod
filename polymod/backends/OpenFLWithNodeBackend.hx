package polymod.backends;

#if (lime && !macro)
import lime.app.Future;
import lime.graphics.Image;
import lime.media.AudioBuffer;
import lime.text.Font;
import lime.utils.AssetLibrary;
import lime.utils.AssetType;
import lime.utils.Assets;
import lime.utils.Bytes;
import polymod.backends.LimeBackend.LimeModLibrary;
#end
#if openfl
import openfl.events.Event;
import openfl.events.EventDispatcher;
#end
import polymod.Polymod.FrameworkParams;

/**
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
/**
  * This class is so mods can be loaded by OpenFL applications running in Electron/Node.
  * IMPORTANT:
  * In order for this to work, you need to configure the BrowserWindow's webPreference
  * for your node application to have 'nodeIntegration' to 'true' and 'contextIsolation' set to 'false'
  * Otherwise, you will not get access to the file system
  *
  * For example:
  * const { app, BrowserWindow } = require('electron')
  * function createWindow () {
  *  const win = new BrowserWindow({
  *    width: 1600,
  *    height: 900,
  *	// frame: false,
  *	useContentSize: true,
  *    webPreferences: { // !!! THE IMPORTANT PART
  *	    nodeIntegration: true, // required for file system access
  *      contextIsolation: false // required for file system access
  *    }
  *  })
  *}
  *
 */
/**
 * @author Tamar Curry
 */
#if (!openfl || !nodefs || nme)
class OpenFLWithNodeBackend extends StubBackend
{
  /**
   * Event that is dispatched when all assets are finished preloading.
   */
  public static inline var FINISHED_PRELOADING_ASSETS:String = 'OpenFLWithNodeBackend.finishedPreloadingAssets';

  // -----------------------------------------------------------------------------------------------
  // -----------------------------------------------------------------------------------------------
  public function new()
  {
    super();
    #if !openfl
    Polymod.error(BACKEND_INIT_FAILED, "OpenFLWithNodeBackend requires the openfl library, did you forget to install it?", INIT);
    #elseif !nodefs
    Polymod.error(BACKEND_INIT_FAILED, 'OpenFLWithNodeBackend requires the nodefs flag to be defined.', INIT);
    #end
  }
}
#else
#if !nme
class OpenFLWithNodeBackend extends OpenFLBackend
{
  /**
   * Event that is dispatched when all assets are finished preloading.
   */
  public static inline var FINISHED_PRELOADING_ASSETS:String = 'OpenFLWithNodeBackend.finishedPreloadingAssets';

  private static var _dispatcher:EventDispatcher;

  public static var dispatcher(get, null):EventDispatcher;

  // -----------------------------------------------------------------------------------------------
  // -----------------------------------------------------------------------------------------------
  public function new()
  {
    super();
  }

  // -----------------------------------------------------------------------------------------------
  override function init(?params:FrameworkParams):Bool
  {
    var result:Bool = super.init(params);

    if (result)
    {
      for (s in modLibraries.keys())
      {
        cast(modLibraries.get(s), OpenFLNodeModLibrary).preloadAssets();
      }
    }

    return result;
  }

  // -----------------------------------------------------------------------------------------------
  override function buildModLibrary(fallbackLibrary, pathPrefix, libraryName):LimeModLibrary
  {
    return new OpenFLNodeModLibrary(this, fallbackLibrary, pathPrefix, libraryName);
  }

  // -----------------------------------------------------------------------------------------------
  private static function get_dispatcher():EventDispatcher
  {
    if (_dispatcher == null)
    {
      _dispatcher = new EventDispatcher();
    }
    return _dispatcher;
  }
}

//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 *
 */
class OpenFLNodeModLibrary extends LimeModLibrary
{
  private var _imagePreloadCount:Int;
  private var _audioPreloadCount:Int;
  private var _fontPreloadCount:Int;
  private var _binaryPreloadCount:Int;

  // -----------------------------------------------------------------------------------------------

  /**
   * Constructor
   * @param	backend
   */
  public function new(backend:OpenFLWithNodeBackend, fallback:AssetLibrary, ?pathPrefix:String = '', ?libraryName:String = '')
  {
    super(backend, fallback, pathPrefix, libraryName);
  }

  // -----------------------------------------------------------------------------------------------

  /**
   * Checks to see what assets were preloaded and if there are any corresponding mod assets to load in their place.
   */
  public function preloadAssets():Void
  {
    var imagesToPreload:Array<String> = [];
    var textToPreload:Array<String> = [];
    var fontsToPreload:Array<String> = [];
    var audioToPreload:Array<String> = [];
    var binaryToPreload:Array<String> = [];

    var t:AssetType;

    // grab the preloaded assets from the fallback and load any replacement assets immediately
    for (s in fallback.preload.keys())
    {
      if (!p.check(s))
      {
        continue;
      }

      t = fallback.types.get(s);

      if (t == AssetType.IMAGE)
      {
        imagesToPreload.push(s);
      }
      else if (t == AssetType.TEXT)
      {
        textToPreload.push(s);
      }
      else if (t == AssetType.FONT)
      {
        fontsToPreload.push(s);
      }
      else if (t == AssetType.SOUND || t == AssetType.MUSIC)
      {
        audioToPreload.push(s);
      }
      else if (t == AssetType.BINARY)
      {
        binaryToPreload.push(s);
      }
    }

    _imagePreloadCount = imagesToPreload.length;
    _audioPreloadCount = audioToPreload.length;
    _fontPreloadCount = fontsToPreload.length;
    _binaryPreloadCount = binaryToPreload.length;

    // text can be loaded immediately
    for (s in textToPreload)
    {
      cachedText.set(s, p.fileSystem.getFileContent(p.getPath(s)));
    }

    // every other asset should go through the usual load process given how loading assets works in HTML5 builds
    for (s in imagesToPreload)
    {
      loadImage(s).onComplete(onImagePreloaded);
    }

    for (s in audioToPreload)
    {
      loadAudioBuffer(s).onComplete(onAudioPreloaded);
    }

    for (s in fontsToPreload)
    {
      loadFont(s).onComplete(onFontPreloaded);
    }

    for (s in binaryToPreload)
    {
      loadBytes(s).onComplete(onBinaryPreloaded);
    }

    checkIfPreloadFinished();
  }

  // -----------------------------------------------------------------------------------------------

  /**
   * Callback for images that are preloading.
   * @param	x
   */
  private function onImagePreloaded(x:Image):Void
  {
    --_imagePreloadCount;
    checkIfPreloadFinished();
  }

  // -----------------------------------------------------------------------------------------------

  /**
   * Callback for audio that is preloading.
   * @param	x
   */
  private function onAudioPreloaded(x:AudioBuffer):Void
  {
    --_audioPreloadCount;
    checkIfPreloadFinished();
  }

  // -----------------------------------------------------------------------------------------------

  /**
   * Callback for font that is preloading.
   * @param	x
   */
  private function onFontPreloaded(x:Font):Void
  {
    --_fontPreloadCount;
    checkIfPreloadFinished();
  }

  // -----------------------------------------------------------------------------------------------

  /**
   * Callback for font that is preloading.
   * @param	x
   */
  private function onBinaryPreloaded(x:Bytes):Void
  {
    --_binaryPreloadCount;
    checkIfPreloadFinished();
  }

  // -----------------------------------------------------------------------------------------------

  /**
   * Check if all assets are finished preloading.
   * If so, dispatch OpenFLWithNodeBackend.FINISHED_PRELOADING_ASSETS
   */
  private function checkIfPreloadFinished():Void
  {
    var isFinished:Bool = true;
    isFinished = isFinished && _imagePreloadCount <= 0;
    isFinished = isFinished && _audioPreloadCount <= 0;
    isFinished = isFinished && _fontPreloadCount <= 0;
    isFinished = isFinished && _binaryPreloadCount <= 0;

    if (isFinished)
    {
      OpenFLWithNodeBackend.dispatcher.dispatchEvent(new Event(OpenFLWithNodeBackend.FINISHED_PRELOADING_ASSETS));
    }
  }

  // -----------------------------------------------------------------------------------------------
  public override function isLocal(id:String, type:String):Bool
  {
    // because images and other assets are loaded asynchronously in HTML5 even if set the data directly,
    // we need to modify the isLocal call to check the cached assets
    if (p.check(id))
    {
      return checkIfAssetIsCached(id, type);
    }
    else if (hasFallback)
    {
      return fallback.isLocal(id, type);
    }
    return false;
  }

  // -----------------------------------------------------------------------------------------------
  public override function getText(id:String):String
  {
    var modText:String = null;

    if (p.check(id))
    {
      modText = cachedText.get(id);
    }
    else if (hasFallback)
    {
      var path:String = fallback.paths.get(id);
      // check the file name for '?' and remove anything after it
      var qIndex:Int = path != null ? path.lastIndexOf('?') : -1;
      if (qIndex > -1)
      {
        path = path.substr(0, qIndex);
      }
      modText = p.fileSystem.getFileContent(path);
    }

    if (modText != null)
    {
      modText = p.mergeAndAppendText(id, modText);
    }
    else
    {
      modText = '';
    }

    return modText;
  }

  // -----------------------------------------------------------------------------------------------
  override public function loadText(id:String):Future<String>
  {
    return Future.withValue(getText(id));
  }

  // -----------------------------------------------------------------------------------------------

  /**
   * Checks if the specified asset has already been loaded.
   * Copied from the origina isLocal function in lime.utils.AssetLibrary
   * @param	id
   * @param	type
   * @return
   */
  private function checkIfAssetIsCached(id:String, type:String):Bool
  {
    if (classTypes.exists(id))
    {
      return true;
    }

    var requestedType = type != null ? cast(type, AssetType) : null;

    return switch (requestedType)
    {
      case IMAGE:
        cachedImages.exists(id);

      case MUSIC, SOUND:
        cachedAudioBuffers.exists(id);

      case FONT:
        cachedFonts.exists(id);

      default: cachedBytes.exists(id) || cachedText.exists(id);
    }
  }
}
#end

#end
