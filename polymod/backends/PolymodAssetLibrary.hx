package polymod.backends;

import haxe.io.Bytes;
import polymod.backends.IBackend;
import polymod.backends.PolymodAssets.PolymodAssetType;
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

typedef PolymodAssetLibraryParams =
{
	/**
	 * the backend used to fetch your default assets
	 */
	backend:IBackend,

	/**
	 * paths to each mod's root directories.
	 * This takes precedence over the 'Dir' parameter and the order matters -- mod files will load from first to last, with last taking precedence
	 */
	dirs:Array<String>,

	/**
	 * the file system used to fetch your mod assets from storage
	 */
	fileSystem:IFileSystem,

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

	/**
	 * (optional) the framework params for the libraries.
	 */
	?frameworkParams:FrameworkParams,

	/**
	 * (optional) a FireTongue instance for Polymod to hook into for localization support
	 */
	#if firetongue
	?firetongue:FireTongue,
	#end
}

class PolymodAssetLibrary
{
	public var backend(default, null):IBackend;
	public var fileSystem(default, null):IFileSystem;

	public var type(default, null):Map<String, PolymodAssetType>;
	public var typeLibraries(default, null):Map<String, Array<String>>;

	public var assetPrefix(default, null):String = "assets/";
	public var dirs:Array<String> = null;
	public var ignoredFiles:Array<String> = null;

	private var parseRules:ParseRules = null;
	private var frameworkParams:FrameworkParams = null;
	private var extensions:Map<String, PolymodAssetType>;

	// Cache for directory listings to avoid repeated file system scans
	private var _dirCache:Map<String, Array<String>> = new Map();
	// Fast lookup for ignored files using Map instead of array searches
	private var _ignoredFilesSet:Map<String, Bool> = null;
	//Cache for file existence checks
	private var _fileExistsCache:Map<String, Bool> = new Map();
	// Cache for asset types to avoid repeated extension parsing
	private var _assetTypeCache:Map<String, PolymodAssetType> = new Map();
	// Pre-built list of all available files across all mods
	private var _allFilesCache:Array<String> = null;
	// Cache for processed text files
	private var _textCache:Map<String, String> = new Map();

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

	public function new(params:PolymodAssetLibraryParams)
	{
		backend = params.backend;
		fileSystem = params.fileSystem;
		backend.polymodLibrary = this;
		dirs = params.dirs;
		parseRules = params.parseRules;
		frameworkParams = params.frameworkParams;
		ignoredFiles = params.ignoredFiles != null ? params.ignoredFiles.copy() : [];
		extensions = params.extensionMap;
		if (params.assetPrefix != null)
			assetPrefix = params.assetPrefix;

		#if firetongue
		tongue = params.firetongue;
		if (tongue != null)
		{
			// Call when we build the asset library then again each time we change locale.
			onFireTongueLoad();
			tongue.addFinishedCallback(onFireTongueLoad);
		}
		#end

		_buildIgnoredSet();
		
		backend.clearCache();
		init();
		
		_buildAllFilesCache();
	}

	#if firetongue
	/**
	 * Do basic initialization based on the FireTongue instance
	 * Must be redone if the locale changes
	 */
	function onFireTongueLoad()
	{
		if (tongue == null)
			return;

		rawTongueDirectory = tongue.directory;
		localePrefix = Util.pathJoin(rawTongueDirectory, tongue.locale);
		localeAssetPrefix = Util.pathJoin(localePrefix, assetPrefix);
		
		// Clear caches when locale changes
		_clearCaches();
	}
	#end

	public function destroy()
	{
		backend?.destroy();
		_clearCaches();
		Polymod.clearScripts();
	}

	private function _clearCaches():Void
	{
		_dirCache = new Map();
		_fileExistsCache = new Map();
		_assetTypeCache = new Map();
		_allFilesCache = null;
		_textCache = new Map();
	}

	public function mergeAndAppendText(id:String, modText:String):String
	{
		var cacheKey = PolymodConfig.mergeFolder + id;
		if (_textCache.exists(cacheKey))
		{
			return _textCache.get(cacheKey);
		}
		
		modText = Util.mergeAndAppendText(modText, id, dirs, getTextDirectly, fileSystem, parseRules);
		
		_textCache.set(cacheKey, modText);
		return modText;
	}

	public function getExtensionType(ext:String):PolymodAssetType
	{
		ext = ext.toLowerCase();
		
		if (_assetTypeCache.exists(ext))
		{
			return _assetTypeCache.get(ext);
		}
		
		var result:PolymodAssetType = BYTES;
		if (extensions != null && extensions.exists(ext))
		{
			result = extensions.get(ext);
		}
		
		_assetTypeCache.set(ext, result);
		return result;
	}

	/**
	 * Get text without consideration of any modifications
	 * @param	id
	 * @param	theDir
	 * @return
	 */
	public function getTextDirectly(id:String, directory:String = ''):String
	{
		var bytes = null;
		if (checkDirectly(id, directory))
		{
			bytes = fileSystem.getFileBytes(file(id, directory));
		}
		else
		{
			bytes = backend.getBytes(id);
		}

		if (bytes == null)
		{
			return null;
		}
		else
		{
			return bytes.getString(0, bytes.length);
		}
	}

	public function exists(id:String):Bool
	{
		return backend.exists(id);
	}

	public function getText(id:String):String
	{
		if (_textCache.exists(id))
		{
			return _textCache.get(id);
		}
		
		var result = backend.getText(id);

		if (result != null)
		{
			_textCache.set(id, result);
		}
		
		return result;
	}

	#if lime
	public function loadText(id:String):lime.app.Future<String>
	{
		return backend.loadText(id);
	}
	#end

	public function getBytes(id:String):Bytes
	{
		return backend.getBytes(id);
	}

	#if lime
	public function loadBytes(id:String):lime.app.Future<Bytes>
	{
		return backend.loadBytes(id);
	}
	#end

	public function getPath(id:String):String
	{
		return backend.getPath(id);
	}

	public function clearCache()
	{
		backend.clearCache();
		_clearCaches();
	}

	public function list(type:PolymodAssetType = null):Array<String>
	{
		// Use pre-built cache when possible
		if (type == null && _allFilesCache != null)
		{
			return _allFilesCache.copy();
		}
		
		return backend.list(type);
	}

	public function listLibraries():Array<String> {
		return backend.listLibraries();
	}

	public function listModFiles(type:PolymodAssetType = null):Array<String>
	{
		// Use pre-built cache
		if (_allFilesCache != null) {
			if (type == null) {
				return _allFilesCache.copy();
			}
			
			var filtered:Array<String> = [];
			for (id in _allFilesCache) {
				if (check(id, type)) {
					filtered.push(id);
				}
			}
			return filtered;
		}

		var items = [];
		for (id in this.type.keys())
		{
			if (items.indexOf(id) != -1)
				continue;
			if (Util.isMergeOrAppend(id))
				continue;
			if (type == null || type == BYTES || check(id, type))
			{
				items.push(id);
			}
		}
		return items;
	}

	/**
	 * Check if the given asset exists in the file system
	 * (If using multiple mods, it will return true if ANY of the mod folders contains this file)
	 * @param	id
	 * @return
	 */
	public function check(id:String, type:PolymodAssetType = null):Bool
	{
		var exists = _checkExists(id);
		if (exists && type != null && type != PolymodAssetType.BYTES)
		{
			var otherType = this.type.get(id);
			exists = (otherType == type || otherType == PolymodAssetType.BYTES || otherType == null || otherType == '');
		}
		return exists;
	}

	public function getType(id:String):PolymodAssetType
	{
		var exists = _checkExists(id);
		if (exists)
		{
			return this.type.get(id);
		}
		return null;
	}

	public function checkDirectly(id:String, dir:String = ''):Bool
	{
		id = stripAssetsPrefix(id);
		if (dir == null || dir == '')
		{
			return _cachedFileSystemExists(id);
		}
		else
		{
			var thePath = Util.uCombine([dir, Util.sl(), id]);
			return _cachedFileSystemExists(thePath);
		}
	}

	/**
	 * Get the filename of the given asset id
	 * (If using multiple mods, it will check all the mod folders for this file, and return the LAST one found)
	 * @param	id
	 * @return
	 */
	public function file(id:String, theDir:String = ''):String
	{
		var idStripped = stripAssetsPrefix(id);
		if (theDir != '')
		{
			if (idStripped.startsWith(theDir)) return idStripped;
			return Util.pathJoin(theDir, idStripped);
		}

		var result = '';
		var resultLocalized = false;
		for (modDir in dirs)
		{
			#if firetongue
			if (localeAssetPrefix != null)
			{
				var localePath = Util.pathJoin(modDir, Util.pathJoin(localeAssetPrefix, idStripped));
				if (_cachedFileSystemExists(localePath))
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
				if (_cachedFileSystemExists(filePath))
					result = filePath;
			}
		}
		return result;
	}

	/**
	 * Get the filename of the given asset id,
	 * with the given locale prefix prepended.
	 * (will ignore all installed mods)
	 */
	public function fileLocale(id:String):String
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

	private function _cachedFileSystemExists(path:String):Bool
	{
		if (_fileExistsCache.exists(path)) {
			return _fileExistsCache.get(path);
		}
		
		var exists = fileSystem.exists(path);
		_fileExistsCache.set(path, exists);
		return exists;
	}

	private function _checkExists(id:String):Bool
	{
		if (isAssetExcluded(id)) return false;

		id = stripAssetsPrefix(id);
		for (d in dirs)
		{
			#if firetongue
			if (localeAssetPrefix != null)
			{
				var localePath = Util.pathJoin(d, Util.pathJoin(localeAssetPrefix, id));
				if (_cachedFileSystemExists(localePath))
					return true;
			}
			// Else, FireTongue not enabled.
			#end

			var filePath = Util.pathJoin(d, id);
			if (_cachedFileSystemExists(filePath))
			{
				return true;
			}
		}
		// The loop didn't find it.
		return false;
	}

	private function init()
	{
		type = [];
		typeLibraries = [ 'default' => [] ];

		// Load libraries from frameworkParams.
		if (frameworkParams != null && frameworkParams.assetLibraryPaths != null)
		{
			for (k in frameworkParams.assetLibraryPaths.keys())
			{
				if (!typeLibraries.exists(k)) typeLibraries.set(k, []);
			}
		}

		initExtensions();
		if (parseRules == null)
			parseRules = ParseRules.getDefault();
		if (dirs != null)
		{
			for (d in dirs)
			{
				initMod(d);
			}
		}
	}

	private function _buildAllFilesCache():Void
	{
		_allFilesCache = [];
		for (id in type.keys())
		{
			if (Util.isMergeOrAppend(id))
				continue;
			_allFilesCache.push(id);
		}
	}

	private function initExtensions()
	{
		if (extensions == null)
			extensions = new Map<String, PolymodAssetType>();

		_extensionSet('mp3', AUDIO_SOUND);
		_extensionSet('ogg', AUDIO_SOUND);
		_extensionSet('wav', AUDIO_SOUND);

		_extensionSet('otf', FONT);
		_extensionSet('ttf', FONT);

		_extensionSet('bmp', IMAGE);
		_extensionSet('gif', IMAGE);
		_extensionSet('jpg', IMAGE);
		_extensionSet('png', IMAGE);
		_extensionSet('tga', IMAGE);
		_extensionSet('tif', IMAGE);
		_extensionSet('tiff', IMAGE);

		_extensionSet('csv', TEXT);
		_extensionSet('hx', TEXT);
		_extensionSet('hxc', TEXT);
		_extensionSet('hxs', TEXT);
		_extensionSet('json', TEXT);
		_extensionSet('md', TEXT);
		_extensionSet('mpf', TEXT);
		_extensionSet('tmx', TEXT);
		_extensionSet('tsv', TEXT);
		_extensionSet('tsx', TEXT);
		_extensionSet('txt', TEXT);
		_extensionSet('vdf', TEXT);
		_extensionSet('xml', TEXT);

		_extensionSet('avi', VIDEO);
		_extensionSet('mkv', VIDEO);
		_extensionSet('mov', VIDEO);
		_extensionSet('mp4', VIDEO);
		_extensionSet('webm', VIDEO);
	}

	private function _extensionSet(str:String, type:PolymodAssetType)
	{
		if (extensions.exists(str) == false)
		{
			extensions.set(str, type);
		}
	}

	private function initMod(d:String):Void
	{
		Polymod.notice(MOD_LOAD_PREPARE, 'Preparing to load mod $d');
		if (d == null)
			return;

		var all:Array<String> = null;

		if (_dirCache.exists(d))
		{
			all = _dirCache.get(d);
		}
		else
		{
			try
			{
				if (_cachedFileSystemExists(d))
				{
					all = fileSystem.readDirectoryRecursive(d);
					_dirCache.set(d, all);
				}
			}
			catch (msg:Dynamic)
			{
				Polymod.error(MOD_LOAD_FAILED, 'Failed to load mod $d : $msg');
				throw('ModAssetLibrary._initMod("$d") failed: $msg');
			}
		}
		
		if (all == null) all = [];
		
		for (f in all)
		{
			var doti = Util.uLastIndexOf(f, '.');
			var ext:String = doti != -1 ? f.substring(doti + 1) : '';
			ext = ext.toLowerCase();
			var assetType = getExtensionType(ext);
			type.set(f, assetType);

			var kruePath:String = f;
			for (folder in [PolymodConfig.mergeFolder, PolymodConfig.appendFolder])
			{
				if (Util.uIndexOf(f, '$folder/') == 0) { kruePath = Util.uSubstring(f, folder.length + 1); break; }
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
							if (!typeLibraries.exists(k)) 
								typeLibraries.set(k, []);
							typeLibraries.get(k).push(f);
							added = true;
							break;
						}
					}
				}
				if (!added) typeLibraries.get('default').push(f);
			}
			else 
			{
				typeLibraries.get('default').push(f);
			}

			#if openfl
			if (assetType == FONT)
			{
				var fontBytes = fileSystem.getFileBytes(file(f, d));
				if (fontBytes != null)
				{
					final font = Font.fromBytes(fontBytes);
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
		Polymod.notice(MOD_LOAD_DONE, 'Done loading mod $d');
	}

	@:allow(polymod.backends.LimeCoreLibrary)
	private function initRedirectPath(libraryId:String, redirectPath:String, pathPrefix:String = '') {
		if (!typeLibraries.exists(libraryId)) {
			typeLibraries.set(libraryId, []);
		}

		if (redirectPath == null || redirectPath == '') return;

		redirectPath = Util.pathJoin(redirectPath, pathPrefix);

		var all:Array<String> = [];

		try {
			if (_cachedFileSystemExists(redirectPath))
			{
				all = fileSystem.readDirectoryRecursive(redirectPath);
			} else {
				Polymod.error(MOD_LOAD_FAILED, 'Failed to load core asset redirect $redirectPath : Directory does not exist!');
				throw('ModAssetLibrary.initRedirectPath("$redirectPath") failed: Directory does not exist!');
			}
		}
		catch (msg:Dynamic)
		{
			Polymod.error(MOD_LOAD_FAILED, 'Failed to load core asset redirect $redirectPath : $msg');
			throw('ModAssetLibrary.initRedirectPath("$redirectPath") failed: $msg');
		}

		for (f in all) {
			var doti = Util.uLastIndexOf(f, '.');
			var ext:String = doti != -1 ? f.substring(doti + 1) : '';
			ext = ext.toLowerCase();
			var assetType = getExtensionType(ext);
			type.set(f, assetType);
			if (!typeLibraries.exists(libraryId)) typeLibraries.set(libraryId, []);
			typeLibraries.get(libraryId).push(f);
			#if openfl
			if (assetType == FONT)
			{
				var fontBytes = fileSystem.getFileBytes(file(f, redirectPath));
				if (fontBytes != null)
				{
					var font = Font.fromBytes(fontBytes);
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
		Polymod.notice(MOD_LOAD_DONE, 'Done loading core asset redirect $redirectPath ($keyCount keys)');
		
		_buildAllFilesCache();
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

	private function _buildIgnoredSet():Void
	{
		_ignoredFilesSet = new Map();
		if (ignoredFiles == null) return;
		
		for (pattern in ignoredFiles)
			_ignoredFilesSet.set(pattern, true);
	}

	public function isAssetExcluded(id:String):Bool
	{
		if (ignoredFiles.length == 0) return false;

		var idStripped = stripAssetsPrefix(id);
		var idPrepend = prependAssetsPrefix(idStripped);

		// TODO: This is MASSIVELY SLOW, any other solutions for this?
		// for (pattern in ignoredFiles) {
		// 	var regex = new EReg('^${pattern}$', 'i');
		// 	if (regex.match(idStripped) || regex.match(idPrepend)) return true;
		// }

		return _ignoredFilesSet.exists(idStripped) || _ignoredFilesSet.exists(idPrepend);
	}
}