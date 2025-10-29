package polymod.backends;

import lime.system.ThreadPool;
import polymod.backends.PolymodAssetLibrary;
import polymod.backends.PolymodAssets.PolymodAssetType;
import polymod.fs.PolymodFileSystem;
import polymod.fs.PolymodFileSystem.IFileSystem;
import polymod.Polymod;
import polymod.Polymod.FrameworkParams;
import polymod.util.Util;
using StringTools;

#if unifill
import unifill.Unifill;
#end
#if (lime && !nme && !macro)
import lime.app.Future;
import lime.graphics.Image;
import lime.net.HTTPRequest;
import lime.text.Font;
import lime.utils.Assets;
import lime.utils.Bytes;
#if openfl
import openfl.text.Font as OpenFLFont;
#end
#if (lime >= '4.0.0')
import lime.media.AudioBuffer;
import lime.utils.AssetLibrary as LimeAssetLibrary;
import lime.utils.AssetType;
#else
import lime.Assets.AssetLibrary as LimeAssetLibrary;
import lime.Assets.AssetType;
import lime.audio.AudioBuffer;
#end
#end
#if (!lime || nme)
class LimeBackend extends StubBackend
{
	public function new()
	{
		super();
		Polymod.error(FAILED_CREATE_BACKEND, "LimeBackend requires the lime library, did you forget to install it?");
	}

	public function preloadImagesToCache():Void {
		Polymod.error(FAILED_CREATE_BACKEND, "LimeBackend requires the lime library, did you forget to install it?");
	}
}
#else
#if (!nme && !macro)
class LimeBackend implements IBackend
{
	// STATIC:
	private static var defaultAssetLibraries:Map<String, LimeAssetLibrary>;

	/**
	 * Find all the registered access libraries and store keyed references to them
	 */
	private static function getDefaultAssetLibraries()
	{
		if (defaultAssetLibraries == null)
		{
			defaultAssetLibraries = new Map<String, LimeAssetLibrary>();

			// I don't like having to do this but there's no other way, hope the internals don't change!
			var libraries = @:privateAccess lime.utils.Assets.libraries;

			// Find every asset library and make a copy of it
			for (key in libraries.keys())
			{
				defaultAssetLibraries.set(key, lime.utils.Assets.getLibrary(key));
			}
		}
		return defaultAssetLibraries;
	}

	/**
	 * Re-register all the asset libraries recorded by `getDefaultAssetLibraries()`
	 */
	private static function restoreDefaultAssetLibraries()
	{
		if (defaultAssetLibraries != null)
		{
			for (key in defaultAssetLibraries.keys())
			{
				Assets.registerLibrary(key, defaultAssetLibraries.get(key));
			}
		}
	}

	// Instance:
	public var polymodLibrary:PolymodAssetLibrary;
	public var modLibraries(default, null):Map<String, LimeModLibrary>;

	public function new()
	{
	}

	public function init(?params:FrameworkParams):Bool
	{
		// Get all the default asset libraries:
		var defaultLibraries = getDefaultAssetLibraries();

		modLibraries = new Map<String, LimeModLibrary>();

		var hasMoreThanDefault = false;
		for (key in defaultLibraries.keys())
		{
			if (key != 'default')
			{
				hasMoreThanDefault = true;
				break;
			}
		}

		if (params == null)
		{
			// Prevent null object reference errors.
			params = {};
		}

		if (hasMoreThanDefault && params.assetLibraryPaths == null)
		{
			Polymod.error(PolymodErrorCode.LIME_MISSING_ASSET_LIBRARY_INFO,
				"Your Lime/OpenFL configuration is using custom asset libraries, but you have not provided the frameworkParams.assetLibraryPaths parameter in Polymod.init() that tells Polymod which asset libraries to expect and what their mod sub-directory prefixes should be.",
				PolymodErrorOrigin.INIT);
			return false;
		}

		// Wrap each asset library in `LimeModLibrary`, register it with Lime, and store it here
		for (key in defaultLibraries.keys())
		{
			var pathPrefix = '';
			if (hasMoreThanDefault)
			{
				if (!params.assetLibraryPaths.exists(key) && key != 'default')
				{
					Polymod.error(PolymodErrorCode.LIME_MISSING_ASSET_LIBRARY_REFERENCE,
						"Your Lime/OpenFL configuration is using custom asset libraries, and you provided frameworkParams in Polymod.init(), but we couldn't find a match for this asset library: (" +
						key + ')',
						PolymodErrorOrigin.INIT);
					return false;
				}
				else
				{
					pathPrefix = params.assetLibraryPaths.get(key) ?? '';
				}
			}
			var fallbackLibrary = defaultLibraries.get(key);
			// Prevent recursion when reinitializing Polymod.
			while (Std.isOfType(fallbackLibrary, LimeModLibrary))
			{
				fallbackLibrary = cast(fallbackLibrary, LimeModLibrary).getFallbackLibrary();
			}

			if (params.coreAssetRedirect != null) {
				fallbackLibrary = new LimeCoreLibrary(this, fallbackLibrary, params.coreAssetRedirect, pathPrefix, key);
			}

			var modLibrary = buildModLibrary(fallbackLibrary, pathPrefix, key);
			modLibraries.set(key, modLibrary);
		}

		for (key in modLibraries.keys())
		{
			registerLibrary(key, modLibraries.get(key));
		}

		return true;
	}

	function buildModLibrary(fallbackLibrary:LimeAssetLibrary, pathPrefix:String, libraryId:String):LimeModLibrary
	{
		return new LimeModLibrary(this, fallbackLibrary, pathPrefix, libraryId);
	}

	function registerLibrary(name:String, library:LimeAssetLibrary):Void
	{
		if (name == null || name == "")
		{
			name = "default";
		}

		@:privateAccess
		if (lime.utils.Assets.libraries.exists(name))
		{
			@:privateAccess
			if (lime.utils.Assets.libraries.get(name) == library)
			{
				return;
			}
			else
			{
				unloadLibrary(name);
			}
		}

		if (library != null)
		{
			@:privateAccess
			library.onChange.add(lime.utils.Assets.library_onChange);
		}

		@:privateAccess
		lime.utils.Assets.libraries.set(name, library);
	}

	function unloadLibrary(name:String):Void
	{
		#if (tools && !display)
		if (name == null || name == "")
		{
			name = "default";
		}

		@:privateAccess
		var library = lime.utils.Assets.libraries.get(name);

		if (library != null)
		{
			// lime.utils.Assets.cache.clear(name + ":");
			@:privateAccess
			library.onChange.remove(lime.utils.Assets.library_onChange);
			// library.unload();
		}

		@:privateAccess
		lime.utils.Assets.libraries.remove(name);
		#end
	}

	/**
	 * Gets called when the backend is being destroyed.
	 * This happens when `Polymod.init()` is called again, which means mods are being reloaded.
	 */
	public function destroy()
	{
		polymodLibrary = null;
		restoreDefaultAssetLibraries();
		for (key in modLibraries.keys())
		{
			var modLibrary = modLibraries.get(key);
			modLibrary.destroy();
			modLibraries.remove(key);
		}
		modLibraries = null;
	}

	public function exists(id:String):Bool
	{
		var symbol = new IdAndLibrary(id, modLibraries);
		return symbol.exists();
	}

	public function getBytes(id:String):Bytes
	{
		var symbol = new IdAndLibrary(id, modLibraries);
		var bytes = symbol.library.getBytes(symbol.modId);
		return bytes;
	}

	public function getText(id:String):String
	{
		var symbol = new IdAndLibrary(id, modLibraries);
		var text = symbol.library.getText(symbol.modId);
		return text;
	}

	public function loadBytes(id:String):lime.app.Future<Bytes>
	{
		var symbol = new IdAndLibrary(id, modLibraries);
		var bytesFuture = symbol.library.loadBytes(symbol.modId);
		return bytesFuture;
	}

	public function loadText(id:String):lime.app.Future<String>
	{
		var symbol = new IdAndLibrary(id, modLibraries);
		var textFuture = symbol.library.loadText(symbol.modId);
		return textFuture;
	}

	public function getPath(id:String):String
	{
		var symbol = new IdAndLibrary(id, modLibraries);
		var path = symbol.library.getPath(symbol.modId);
		return path;
	}

	public function list(type:PolymodAssetType = null):Array<String>
	{
		if (modLibraries == null)
			return [];

		var arr = [];
		for (modLibrary in modLibraries)
		{
			// Get the list of all assets.
			var items = modLibrary.list(null);

			// Filter out assets that don't match the type.
			items = items.filter(function(item:String):Bool
			{
				// Use existsPoly() instead of exists() because exists() converts to a LimeAssetType.
				return modLibrary.existsPoly(item, type);
			});

			// Add the assets to the list.
			arr = arr.concat(items);
		}

		// Filter out duplicates.
		arr = Util.filterUnique(arr);

		return arr;
	}

	public function listLibraries():Array<String> {
		if (modLibraries == null)
			return [];

		return [for (i in modLibraries.keys()) i];
	}

	public function clearCache()
	{
		if (defaultAssetLibraries != null)
		{
			for (key in Assets.cache.audio.keys())
			{
				Assets.cache.audio.remove(key);
			}
			for (key in Assets.cache.font.keys())
			{
				Assets.cache.font.remove(key);
			}
			for (key in Assets.cache.image.keys())
			{
				Assets.cache.image.remove(key);
			}
		}
	}

	public function preloadImagesToCache():Void
	{
		// On HTML5, we need to call `loadImage()` on all images before they can be later loaded synchronously.
		for (modLibrary in modLibraries)
		{
			modLibrary.preloadImagesToCache();
		}
	}
}

class LimeModLibrary extends LimeAssetLibrary
{
	public static function LimeToPoly(type:AssetType):PolymodAssetType
	{
		if (type == null)
			return null;
		return switch (type)
		{
			case AssetType.BINARY: PolymodAssetType.BYTES;
			case AssetType.FONT: PolymodAssetType.FONT;
			case AssetType.IMAGE: PolymodAssetType.IMAGE;
			case AssetType.MUSIC: PolymodAssetType.AUDIO_MUSIC;
			case AssetType.SOUND: PolymodAssetType.AUDIO_SOUND;
			case AssetType.MANIFEST: PolymodAssetType.MANIFEST;
			case AssetType.TEMPLATE: PolymodAssetType.TEMPLATE;
			case AssetType.TEXT: PolymodAssetType.TEXT;
			default: PolymodAssetType.UNKNOWN;
		}
	}

	public static function PolyToLime(type:PolymodAssetType):AssetType
	{
		if (type == null)
			return null;
		return switch (type)
		{
			case PolymodAssetType.BYTES: AssetType.BINARY;
			case PolymodAssetType.TEXT: AssetType.TEXT;
			case PolymodAssetType.IMAGE: AssetType.IMAGE;
			case PolymodAssetType.FONT: AssetType.FONT;
			case PolymodAssetType.AUDIO_GENERIC: AssetType.SOUND;
			case PolymodAssetType.AUDIO_MUSIC: AssetType.MUSIC;
			case PolymodAssetType.AUDIO_SOUND: AssetType.SOUND;
			case PolymodAssetType.MANIFEST: AssetType.MANIFEST;
			case PolymodAssetType.TEMPLATE: AssetType.TEMPLATE;
			// case PolymodAssetType.VIDEO:
			// case PolymodAssetType.UNKNOWN: AssetType.BINARY;
			default: AssetType.BINARY;
		}
	}

	public var pathPrefix:String;
	public var libraryId:String;

	var b:LimeBackend;
	var p:PolymodAssetLibrary;
	var fallback:Null<LimeAssetLibrary>;
	var type(default, null):Map<String, AssetType>;
	var hasFallback(get, null):Bool;
	function get_hasFallback():Bool {
		return fallback != null;
	}

	#if html5
	/**
	 * Preload images on HTML5 to allow images to be loaded synchronously.
	 * This doesn't break mods.
	 */
	var imageCache:Map<String, lime.graphics.Image>;
	#end

	public function new(backend:LimeBackend, fallback:LimeAssetLibrary, ?pathPrefix:String = '', ?libraryId:String = 'default')
	{
		b = backend;
		p = b.polymodLibrary;
		this.pathPrefix = pathPrefix;
		this.libraryId = libraryId;
		this.fallback = fallback;
		#if html5
		imageCache = new Map<String, lime.graphics.Image>();
		// preloadImagesToCache();
		#end
		super();
	}

	public function destroy()
	{
		b = null;
		p = null;
		fallback = null;
		type = null;
	}

	public function getFallbackLibrary():LimeAssetLibrary
	{
		return fallback;
	}

	public function preloadImagesToCache():Void
	{
		// On HTML5, we need to call `loadImage()` on all images before they can be later loaded synchronously.

		for (imageAsset in this.list(AssetType.IMAGE))
		{
			var symbol = new IdAndLibrary(imageAsset, this);
			var filePath = p.file(symbol.modId);

			#if html5
			if (imageCache.exists(filePath))
				continue;
			#end

			loadImage(imageAsset);
		}
	}

	public override function getAsset(id:String, type:String):Dynamic
	{
		if (type == TEXT)
			return getText(id);

		var symbol = new IdAndLibrary(id, this);

		// Check for a modded asset.
		if (p.check(symbol.modId, LimeToPoly(cast type)))
		{
			// Load the modded asset.
			return super.getAsset(id, type);
		}
		else if (hasFallback)
		{
			// Load the base asset.
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.getAsset(localePath, type);
			else
				return fallback.getAsset(id, type);
		}
		// No fallback.
		return null;
	}

	/**
	 * Returns true if the asset of the given id and type exists.
	 		* Takes into account mods and locales, if available.
	 */
	public override function exists(id:String, type:String):Bool
	{
		if (id == null) return false;

		var symbol = new IdAndLibrary(id, this);
		// We have to convert the LimeAssetType to a PolymodAssetType.
		if (p.check(symbol.modId, LimeToPoly(cast type)))
		{
			// Found a modded asset.
			return true;
		}
		else if (hasFallback)
		{
			// Check the base asset.
			return existsDefault(id, type);
		}
		// No fallback.
		return false;
	}

	// When are they going to add overloads ugh.
	public function existsPoly(id:String, type:PolymodAssetType):Bool
	{
		if (id == null) return false;

		var symbol = new IdAndLibrary(id, this);
		if (p.check(symbol.modId, type))
		{
			// Found a modded asset.
			return true;
		}
		else if (hasFallback)
		{
			// Check the base asset.
			return existsDefault(id, type);
		}
		// No fallback.
		return false;
	}

	/**
	 * Returns true if the asset of the given id and type exists.
	 * Takes into account locales, but not mods.
	 */
	function existsDefault(id:String, type:String):Bool
	{
		#if firetongue
		if (p.localePrefix != null)
		{
			var localePath = Util.pathJoin(p.localePrefix, p.prependAssetsPrefix(id));
			if (fallback.exists(localePath, type))
			{
				return true;
			}
		}
		// Else, FireTongue not enabled.
		#end
		return fallback.exists(id, type);
	}

	public override function getAudioBuffer(id:String):AudioBuffer
	{
		var symbol = new IdAndLibrary(id, this);
		if (p.check(symbol.modId))
		{
			return AudioBuffer.fromBytes(p.fileSystem.getFileBytes(p.file(symbol.modId)));
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.getAudioBuffer(localePath);
			else
				return fallback.getAudioBuffer(id);
		}
		return null;
	}

	public override function getBytes(id:String):Bytes
	{
		var symbol = new IdAndLibrary(id, this);
		var file = p.file(symbol.modId);
		if (p.check(symbol.modId))
		{
			return p.fileSystem.getFileBytes(p.file(symbol.modId));
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.getBytes(localePath);
			else
				return fallback.getBytes(id);
		}
		return null;
	}

	public override function getFont(id:String):Font
	{
		var symbol = new IdAndLibrary(id, this);
		if (p.check(symbol.modId))
		{
			var font = #if openfl OpenFLFont #else Font #end.fromBytes(p.fileSystem.getFileBytes(p.file(symbol.modId)));
			#if openfl
			@:privateAccess if (!OpenFLFont.__fontByName.exists(font.name))
				OpenFLFont.registerFont(font);
			#end

			return font;
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.getFont(localePath);
			else
				return fallback.getFont(id);
		}
		return null;
	}

	public override function getImage(id:String):Image
	{
		var symbol = new IdAndLibrary(id, this);
		if (p.check(symbol.modId))
		{
			#if html5
			// NOTE: HTML5 does not like Images.fromBytes because images can't be loaded synchronously.
			// So we cache the image data in a Bytes object and load it asynchronously.
			var filePath = p.file(symbol.modId);
			if (imageCache.exists(filePath))
			{
				return imageCache.get(filePath);
			}
			else
			{
				// LimeBackend has a function to precache mod images when a mod is added,
				// and any HTML5-based file systems need to call it.

				// If the image isn't cached, tough luck.
				return null;
			}
			#else
			// Other platforms don't have these issues with images,
			// and other file types can be loaded synchronously.
			return Image.fromBytes(p.fileSystem.getFileBytes(p.file(symbol.modId)));
			#end
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.getImage(localePath);
			else
				return fallback.getImage(id);
		}
		return null;
	}

	public override function getPath(id:String):String
	{
		var symbol = new IdAndLibrary(id, this);
		if (p.check(symbol.modId))
		{
			return p.file(symbol.modId);
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.getPath(localePath);
			else
				return fallback.getPath(id);
		}
		return null;
	}

	public override function getText(id:String):String
	{
		var symbol = new IdAndLibrary(id, this);
		var modText = null;
		if (p.check(symbol.modId))
		{
			// Don't worry, getText falls back to calling getBytes.
			modText = super.getText(symbol.modId);
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				modText = fallback.getText(localePath);
			else
				modText = fallback.getText(id);
		}

		if (modText != null)
		{
			// TODO: Ensure _merge and _append work with alternate asset libraries.
			modText = p.mergeAndAppendText(id, modText);
		}

		return modText;
	}

	public override function loadBytes(id:String):Future<Bytes>
	{
		var symbol = new IdAndLibrary(id, this);
		var file = p.file(symbol.modId);
		if (p.check(symbol.modId))
		{
			return LimeAsyncHandler.loadBytesFromFileSystem(p.file(symbol.modId), p.fileSystem);
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.loadBytes(localePath);
			else
				return fallback.loadBytes(id);
		}
		return Bytes.loadFromFile('');
	}

	public override function loadFont(id:String):Future<Font>
	{
		var symbol = new IdAndLibrary(id, this);
		if (p.check(symbol.modId))
		{
			#if (js && html5)
			return Font.loadFromName(getPath(p.file(symbol.modId)));
			#else
			return Font.loadFromFile(getPath(p.file(symbol.modId)));
			#end
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.loadFont(localePath);
			else
				return fallback.loadFont(id);
		}
		#if (js && html5)
		return Font.loadFromName(getPath(''));
		#else
		return Font.loadFromFile(getPath(''));
		#end
	}

	public override function loadImage(id:String):Future<Image>
	{
		var symbol = new IdAndLibrary(id, this);
		if (p.check(symbol.modId))
		{
			// We load the bytes, then load the file, rather than using Image.loadFromFile,
			// because URLs don't work with MemoryFileSystem.

			var filePath = p.file(symbol.modId);
			var imageFuture = LimeAsyncHandler.loadBytesFromFileSystem(filePath, p.fileSystem)
				.then((bytes:Bytes) -> {
					return Image.loadFromBytes(bytes);
				});

			#if html5
			imageFuture.onComplete((result:Image) ->
			{
				if (result != null)
				{
					imageCache.set(filePath, result);
				}
			});
			#end

			return imageFuture;
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.loadImage(localePath);
			else
				return fallback.loadImage(id);
		}
		return Image.loadFromFile('');
	}

	public override function loadAudioBuffer(id:String)
	{
		var symbol = new IdAndLibrary(id, this);
		if (p.check(symbol.modId))
		{
			if (pathGroups.exists(p.file(symbol.modId)))
			{
				return AudioBuffer.loadFromFiles(pathGroups.get(p.file(symbol.modId)));
			}
			else
			{
				return AudioBuffer.loadFromFile(getPath(p.file(symbol.modId)));
			}
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.loadAudioBuffer(localePath);
			else
				return fallback.loadAudioBuffer(id);
		}
		return AudioBuffer.loadFromFile('');
	}

	public override function loadText(id:String):Future<String>
	{
		var symbol = new IdAndLibrary(id, this);
		if (p.check(symbol.modId))
		{
			var filePath = p.file(symbol.modId);
			var textFuture = LimeAsyncHandler.loadBytesFromFileSystem(filePath, p.fileSystem)
				.then((bytes:Bytes) -> {
					// Convert the bytes to a string with UTF-8 encoding.
					var modText = bytes.toString();
					if (modText != null)
					{
						modText = p.mergeAndAppendText(id, modText);
					}
					return Future.withValue(modText);
				});

			return textFuture;
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.loadText(localePath);
			else
				return fallback.loadText(id);
		}
		var request = new HTTPRequest<String>();
		return request.load('');
	}

	public override function isLocal(id:String, type:String):Bool
	{
		var symbol = new IdAndLibrary(id, this);
		if (p.check(symbol.modId))
		{
			return true;
		}
		else if (hasFallback)
		{
			var localePath = p.fileLocale(id);
			if (fallback.exists(localePath, null))
				return fallback.isLocal(localePath, type);
			else
				return fallback.isLocal(id, type);
		}
		return false;
	}

	public override function list(requestedType:String):Array<String>
	{
		var polyType = LimeToPoly(cast requestedType);
		var fallbackList:Array<String> = hasFallback ? fallback.list(requestedType) : [];
		var limeType:AssetType = requestedType != null ? cast(requestedType, AssetType) : null;

		var items:Array<String> = [];

		var addItem = (path:String) ->
		{
			if (items.indexOf(path) == -1)
			{
				items.push(path);
			}
		};

		var libraryItems = p.typeLibraries.get(libraryId) ?? [];
		for (id in libraryItems)
		{
			// Skip ignored files.
			if (p.isAssetExcluded(id)) continue;

			// Skip append/merge files.
			if (Util.isMergeOrAppend(id))
				continue;

			#if firetongue
			if (id.startsWith(p.localeAssetPrefix))
			{
				var assetId = Util.stripPathPrefix(id, p.localeAssetPrefix);
				if (id.startsWith(p.assetPrefix))
					assetId = p.prependAssetsPrefix(assetId);
				var symbol = new IdAndLibrary(assetId, this);
				// Skip entries that aren't part of this library.
				if (!symbol.exists()) {
					continue;
				}
				addItem(symbol.modId);
			}
			else
			#end
			// p.type(id) == requestedType is quicker than exists()!
			if (limeType == null || p.type.get(id) == polyType)
			{
				var assetId = p.prependAssetsPrefix(id);
				var symbol = new IdAndLibrary(assetId, this);
				// Skip entries that aren't part of this library.
				if (!symbol.exists()) {
					continue;
				}
				addItem(symbol.modId);
			}
		}

		// Properly handle FireTongue assets.
		// We want to:
		// - Exclude any assets not in the current locale.
		// - Include any assets in the current locale's asset folder as though they were in the root asset folder.
		// - Include other assets (such as FireTongue data files) as though they were in the locale folder.
		// NOTE: We don't need to query exists(id, type) here because otherwise fallbackList wouldn't include it.
		for (fallbackId in fallbackList)
		{
			#if firetongue
			if (p.rawTongueDirectory != null && fallbackId.startsWith(p.rawTongueDirectory))
			{
				// Localized file (example: assets/locales/en-US/...)
				if (fallbackId.startsWith(p.localeAssetPrefix))
				{
					// Localized asset file in CURRENT locale! (example: assets/locales/en-US/assets/...)
					if (requestedType == null || fallback.exists(fallbackId, limeType))
					{
						// The asset in the current locale should 'silently' override the default.
						// We should register this with the locale path prefix removed.
						var assetId = Util.stripPathPrefix(fallbackId, p.localeAssetPrefix);
						if (fallbackId.startsWith(p.assetPrefix))
							assetId = p.prependAssetsPrefix(assetId);
						var symbol = new IdAndLibrary(assetId, this);
						addItem(symbol.modId);
					}
				}
				else
				{
					// Localized FireTongue data file, or asset file in other locale! (example: assets/locales/en-US/data.tsv)
					var assetId = fallbackId;
					var symbol = new IdAndLibrary(assetId, this);
					// The asset in other locales should be added to the list normally.
					addItem(symbol.modId);
				}
			}
			else
			{
				// Unlocalized asset. Handle the original path.
				var assetId = fallbackId;
				var symbol = new IdAndLibrary(assetId, this);
				addItem(symbol.modId);
			}
			#else
			// Unlocalized asset. Handle the original path.
			var assetId = fallbackId;
			var symbol = new IdAndLibrary(assetId, this);
			addItem(symbol.modId);
			#end
		}

		items = Util.filterUnique(items);
		return items;
	}

	public override function load():Future<LimeAssetLibrary>
	{
		return super.load();
	}
}

/**
 * Mostly copied from lime._internal.backend.native.NativeHTTPRequest.
 * https://github.com/openfl/lime/blob/develop/src/lime/_internal/backend/native/NativeHTTPRequest.hx#L285
 */
class LimeAsyncHandler {
	private static var localThreadPool:ThreadPool;

	@:haxe.warning("-WDeprecated")
	static function initThreadPool() {
		if (localThreadPool == null) {
			localThreadPool = new ThreadPool(0, 1);
			localThreadPool.doWork.add(localThreadPool_doWork);
			localThreadPool.onProgress.add(localThreadPool_onProgress);
			localThreadPool.onComplete.add(localThreadPool_onComplete);
			localThreadPool.onError.add(localThreadPool_onError);
		}
	}

	/**
	 * Tell the thread pool to asynchronously load the bytes at the given path from the given file system.
	 * @param path The string path to load the bytes from.
	 * @param fileSystem The IFilesystem to use when loading the bytes.
	 * @return A future promising that the bytes will be made available when the task is complete.
	 */
	public static function loadBytesFromFileSystem(path:String, fileSystem:IFileSystem):Future<Bytes> {
		initThreadPool();

		var promise = new lime.app.Promise<Bytes>();

		localThreadPool.queue({
			task: "loadBytesFromFileSystem",
			path: path,
			fileSystem: fileSystem,
			promise: promise
		});

		return promise.future;
	}

	static function localThreadPool_doWork(state:Dynamic):Void {
		var task:String = state.task;
		var path:String = state.path;
		var fileSystem:IFileSystem = state.fileSystem;
		var promise:lime.app.Promise<Bytes> = state.promise;

		switch (task) {
			case "loadBytesFromFileSystem":
				var result:Bytes = fileSystem.getFileBytes(path);
				localThreadPool.sendProgress({
					bytesLoaded: result.length,
					bytesTotal: result.length,
					promise: promise
				});
				localThreadPool.sendComplete({
					result: result,
					promise: promise
				});
				promise.complete(result);
			default:
				localThreadPool.sendError("Invalid task: " + task);
		}
	}

	static function localThreadPool_onProgress(state:Dynamic):Void {
		var promise = state.promise;
		var bytesLoaded = state.bytesLoaded;
		var bytesTotal = state.bytesTotal;
		if (promise.isComplete || promise.isError) return;
		promise.progress(bytesLoaded, bytesTotal);
	}

	static function localThreadPool_onError(state:Dynamic):Void {
		var promise = state.promise;
		var error = state.error;
		promise.error(error);
	}

	static function localThreadPool_onComplete(state:Dynamic):Void {
		var promise = state.promise;
		var result = state.result;
		if (promise.isError || result == null) return;
		promise.complete(result);
	}
}

/**
 * An asset library which redirects all requests to another folder.
 */
@:access(lime.utils.AssetLibrary)
class LimeCoreLibrary extends LimeAssetLibrary {
	public final redirectPath:String;

	var backend:LimeBackend;
	var polymodLibrary(get, null):PolymodAssetLibrary;
	function get_polymodLibrary():PolymodAssetLibrary {
		return backend.polymodLibrary;
	}
	var fallback:Null<LimeAssetLibrary>;
	var hasFallback(get, null):Bool;
	function get_hasFallback():Bool {
		return fallback != null;
	}
	var pathPrefix:String;
	var libraryId:String;

	#if html5
	/**
	 * Preload images on HTML5 to allow images to be loaded synchronously.
	 * This doesn't break mods because a new
	 */
	var imageCache:Map<String, lime.graphics.Image>;
	#end

	public function new(backend:LimeBackend, fallback:LimeAssetLibrary, redirectPath:String, pathPrefix:String, libraryId:String) {
		super();
		this.backend = backend;
		this.fallback = fallback;
		this.redirectPath = redirectPath;
		this.pathPrefix = pathPrefix;
		this.libraryId = libraryId;

		polymodLibrary.initRedirectPath(libraryId, redirectPath, pathPrefix);
	}

	function buildRedirectId(id:String):String {
		var baseId = if (pathPrefix == '') {
			if (libraryId != 'default') {
				// Util.pathJoin(libraryId, polymodLibrary.stripAssetsPrefix(id));
				polymodLibrary.stripAssetsPrefix(id);
			} else {
				polymodLibrary.stripAssetsPrefix(id);
			}
		} else {
			var strippedId = Util.stripPathPrefix(polymodLibrary.stripAssetsPrefix(id), pathPrefix);
			Util.pathJoin(pathPrefix, strippedId);
		}

		return Util.pathJoin(redirectPath, baseId);
	}

	public override function exists(id:String, type:String):Bool {
		if (id == null) return false;

		// TODO: No `type` check here?
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			return true;
		}

		return fallback.exists(id, type);
	}

	public override function getAsset(id:String, type:String):Dynamic {
		// Calls one of the other get* functions.
		return super.getAsset(id, type);
	}

	public override function getAudioBuffer(id:String):AudioBuffer {
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			return AudioBuffer.fromBytes(polymodLibrary.fileSystem.getFileBytes(redirectId));
		}
		return fallback.getAudioBuffer(id);
	}
	public override function getBytes(id:String):Bytes {
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			return polymodLibrary.fileSystem.getFileBytes(redirectId);
		}
		return fallback.getBytes(id);
	}
	public override function getFont(id:String):Font {
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			var font = #if openfl OpenFLFont #else Font #end.fromBytes(polymodLibrary.fileSystem.getFileBytes(redirectId));
			#if openfl
			@:privateAccess if (!OpenFLFont.__fontByName.exists(font.name))
				OpenFLFont.registerFont(font);
			#end
		}

		return fallback.getFont(id);
	}
	public override function getImage(id:String):Image {
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			return Image.fromBytes(polymodLibrary.fileSystem.getFileBytes(redirectId));
		}
		return fallback.getImage(id);
	}
	public override function getText(id:String):String {
		// super.getText() just uses getBytes().
		return super.getText(id);
	}

	public override function getPath(id:String):String {
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			return redirectId;
		}
		return fallback.getPath(id);
	}
	public override function isLocal(id:String, type:String):Bool {
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			return true;
		}
		return fallback.isLocal(id, type);
	}

	public override function loadBytes(id:String):Future<Bytes>
	{
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			return Bytes.loadFromFile(redirectId);
		}

		return fallback.loadBytes(id);
	}

	public override function loadFont(id:String):Future<Font>
	{
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			#if (js && html5)
			return Font.loadFromName(getPath(redirectId));
			#else
			return Font.loadFromFile(getPath(redirectId));
			#end
		}

		return fallback.loadFont(id);
	}

	public override function loadImage(id:String):Future<Image>
	{
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			// TODO: What was this line for? This is already the redirect ID.
			// var filePath = polymodLibrary.file(redirectId);

			// We load the bytes, then load the file, rather than using Image.loadFromFile,
			// because URLs don't work with MemoryFileSystem.
			var dabytes = polymodLibrary.fileSystem.getFileBytes(redirectId);
			var imageFuture = Image.loadFromBytes(dabytes);

			return imageFuture;
		}

		return fallback.loadImage(id);
	}

	public override function loadAudioBuffer(id:String)
	{
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			return AudioBuffer.loadFromFile(redirectId);
		}

		return fallback.loadAudioBuffer(id);
	}

	public override function loadText(id:String):Future<String>
	{
		var redirectId:String = buildRedirectId(id);
		if (polymodLibrary.fileSystem.exists(redirectId)) {
			var request = new HTTPRequest<String>();
			return request.load(redirectId).then((modText) ->
			{
				if (modText != null)
				{
					modText = polymodLibrary.mergeAndAppendText(id, modText);
				}
				return Future.withValue(modText);
			});
		}

		return fallback.loadText(id);
	}

	public override function list(type:String):Array<String>
	{
		var fallbackList = hasFallback ? fallback.list(type) : [];

		var requestedType = type != null ? cast(type, AssetType) : null;
		var items = [];

		var addItem = (path:String) ->
		{
			// Only add unique items.
			if (items.indexOf(path) == -1) items.push(path);
		};

		for (id in fallbackList) {
			addItem(id);
		}

		// If using a redirect path, this ends up including files that exist in the redirect path
		// that are excluded in the fallback library.
		var fileList:Array<String> = polymodLibrary.fileSystem.readDirectoryRecursive(Util.pathJoin(redirectPath, pathPrefix));
		for (id in fileList) {
			var basePath = polymodLibrary.stripAssetsPrefix(id);
			// if (libraryId != 'default') {
			// 	Util.pathJoin(libraryId, polymodLibrary.stripAssetsPrefix(id));
			// } else {
			// }

			var prefixedId:String = polymodLibrary.prependAssetsPrefix(basePath);

			// Exclude files in the `ignoredFiles` list.
			if (polymodLibrary.isAssetExcluded(basePath)) continue;

			addItem(prefixedId);
		}

		return Util.filterUnique(items);
	}
	public override function load():Future<LimeAssetLibrary>
	{
		return super.load();
	}
}

/**
 * This helper class helps me deal with all the path nonsense of custom asset library asset calls
 * e.g. asking library 'foo' for 'bar.png' will result in:
 *   id = 'foo:bar.png'
 *   lib = 'foo'
 *   library = the 'foo' library
 *   nakedId = 'bar.png'
 *   modId = 'foo/bar.png' (assuming 'foo' is the mod path prefix for the 'foo' library)
 *   fallbackId = 'foo:bar.png'
 */
private class IdAndLibrary
{
	public var library(default, null):LimeModLibrary;
	public var lib(default, null):String;
	public var modId(default, null):String;
	public var nakedId(default, null):String;
	public var fallbackId(default, null):String;

	public var fullId(get, never):String;

	function get_fullId():String {
		if (lib == null || lib == 'default' || lib == '') {
			return modId;
		}
		return '${lib}:$nakedId';
	}

	public inline function new(id:String, ?libs:Map<String, LimeModLibrary>, ?l:LimeModLibrary)
	{
		fallbackId = id;
		var colonIndex = id.indexOf(':');
		lib = id.substring(0, colonIndex);
		nakedId = id.substring(colonIndex + 1);
		if (l != null)
		{
			library = l;
			if (lib == '' || lib == null)
			{
				lib = library.libraryId ?? 'default';
			}
		}
		else if (libs != null)
		{
			if (lib == '' || lib == null)
			{
				lib = 'default';
			}
			library = libs.get(lib);
		}
		modId = nakedId;
	}

	public function exists():Bool {
		return this.library.exists(this.modId, null);
	}
}
#end

#end
