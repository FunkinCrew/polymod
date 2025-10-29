package polymod;

import polymod.util.DefineUtil;

/**
 * This class provides several constants used throughout the library.
 * You can define these values in your `hxml` or `project.xml` using haxe defines,
 * or just set them in your code before you load any classes that implement HScriptable.
 */
class PolymodConfig
{
	/**
	 * If true, additional debug output will be provided by Polymod.
	 * 
	 * Set this option by setting the `POLYMOD_DEBUG` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `false`
	 */
	public static var debug(get, default):Null<Bool>;

	static function get_debug():Null<Bool>
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (debug == null)
			debug = DefineUtil.getDefineBool('POLYMOD_DEBUG', false);
		return debug;
	}

	/**
	 * The base path from which scripts should be accessed.
	 * 
	 * Set this option by setting the `POLYMOD_ROOT_PATH` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `data/`
	 */
	public static var rootPath(get, default):String;

	static function get_rootPath():String
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (rootPath == null)
			rootPath = DefineUtil.getDefineString('POLYMOD_ROOT_PATH', 'data/');
		return rootPath;
	}

	/**
	 * Whether script paths should, by default, be relative to the class's path or the root path.
	 * For example, if true, `demo.Simulation#updateBee` will use `data/demo/Simulation/updateBee.txt`
	 * If false, `demo.Simulation#updateBee` will use `data/updateBee.txt`
	 * 
	 * Set this option by setting the `POLYMOD_USE_NAMESPACE` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `true`
	 */
	public static var useNamespaceInPaths(get, default):Null<Bool>;

	static function get_useNamespaceInPaths():Null<Bool>
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (useNamespaceInPaths == null)
			useNamespaceInPaths = DefineUtil.getDefineBool('POLYMOD_USE_NAMESPACE', true);
		return useNamespaceInPaths;
	}

	/**
	 * The file extension for script files. It is recommended to change this to `.hxs`.
	 * 
	 * Set this option by setting the `POLYMOD_SCRIPT_EXT` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `.txt`
	 */
	public static var scriptExt(get, default):String;

	static function get_scriptExt():String
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (scriptExt == null)
			scriptExt = DefineUtil.getDefineString('POLYMOD_SCRIPT_EXT', '.txt');
		return scriptExt;
	}

	/**
	 * The file extension for scripted class files.
	 * 
	 * Set this option by setting the `POLYMOD_SCRIPT_CLASS_EXT` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `.hclass`
	 */
	public static var scriptClassExt(get, default):String;

	static function get_scriptClassExt():String
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (scriptClassExt == null)
			scriptClassExt = DefineUtil.getDefineString('POLYMOD_SCRIPT_CLASS_EXT', '.hxc');
		return scriptClassExt;
	}

	/**
	 * The asset library to use for loading scripts.
	 * Only relevant for Lime/OpenFL projects which use multiple asset libraries.
	 * 
	 * Set this option by setting the `POLYMOD_SCRIPT_LIBRARY` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `default`
	 */
	public static var scriptLibrary(get, default):String;

	static function get_scriptLibrary():String
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (scriptLibrary == null)
			scriptLibrary = DefineUtil.getDefineString('POLYMOD_SCRIPT_LIBRARY', 'default');
		return scriptLibrary;
	}

	/**
	 * The directory from which to read data append files.
	 * 
	 * Set this option by setting the `POLYMOD_APPEND_FOLDER` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `_append`
	 */
	public static var appendFolder(get, default):String;

	static function get_appendFolder():String
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (appendFolder == null)
			appendFolder = DefineUtil.getDefineString('POLYMOD_APPEND_FOLDER', '_append');
		return appendFolder;
	}

	/**
	 * The directory from which to read data merge files.
	 * 
	 * Set this option by setting the `POLYMOD_MERGE_FOLDER` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `_merge`
	 */
	public static var mergeFolder(get, default):String;

	static function get_mergeFolder():String
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (mergeFolder == null)
			mergeFolder = DefineUtil.getDefineString('POLYMOD_MERGE_FOLDER', '_merge');
		return mergeFolder;
	}

	/**
	 * The file where Polymod checks for modpack definitions.
	 * 
	 * Set this option by setting the `POLYMOD_MOD_PACK_FILE` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `_polymod_pack.txt`
	 */
	// @:deprecated("Functionality removed, new implementation pending")
	public static var modPackFile(get, default):String;

	static function get_modPackFile():String
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (modPackFile == null)
			modPackFile = DefineUtil.getDefineString('POLYMOD_MOD_PACK_FILE', '_polymod_pack.txt');
		return modPackFile;
	}

	/**
	 * The file where Polymod checks for mod metadata.
	 * 
	 * Set this option by setting the `POLYMOD_MOD_METADATA_FILE` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `_polymod_meta.json`
	 */
	public static var modMetadataFile(get, default):String;

	static function get_modMetadataFile():String
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (modMetadataFile == null)
			modMetadataFile = DefineUtil.getDefineString('POLYMOD_MOD_METADATA_FILE', '_polymod_meta.json');
		return modMetadataFile;
	}

	/**
	 * The file where Polymod checks for mod metadata.
	 * 
	 * Set this option by setting the `POLYMOD_MOD_ICON_FILE` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `_polymod_icon.png`
	 */
	public static var modIconFile(get, default):String;

	static function get_modIconFile():String
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (modIconFile == null)
			modIconFile = DefineUtil.getDefineString('POLYMOD_MOD_ICON_FILE', '_polymod_icon.png');
		return modIconFile;
	}

	/**
	 * The files which Polymod should ignore when loading mods.
	 * Defaults to the list of license files.
	 * 
	 * Set this option by setting the `POLYMOD_MOD_IGNORE` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `LICENSE.txt,ASSET_LICENSE.txt,CODE_LICENSE.txt`
	 */
	public static var modIgnoreFiles(get, default):Array<String>;

	static function get_modIgnoreFiles():Array<String>
	{
		// If the value is null, retrieve the value as a Haxe define.
		if (modIgnoreFiles == null)
			modIgnoreFiles = DefineUtil.getDefineStringArray('POLYMOD_MOD_IGNORE', ['LICENSE.txt', 'ASSET_LICENSE.txt', 'CODE_LICENSE.txt']);
		return modIgnoreFiles;
	}

	/**
	 * If true, assets from ZIP mods will be loaded in a case-insensitive manner.
	 * For example, if trying to load an asset called `FOO.txt`, a file called `foo.txt` will be loaded if it exists.
	 * If multiple files with the same name but differing in letter case exist
	 * in the same directory the choice of which file is loaded is undefined.
	 * 
	 * Disable this option by setting the `POLYMOD_ZIP_INSENSITIVE` Haxe define at compile time,
	 * or by setting this value in your code.
	 * 
	 * @default `true`
	 */
	 public static var caseInsensitiveZipLoading(get, default):Null<Bool>;

	 static function get_caseInsensitiveZipLoading():Null<Bool>
	 {
		if (caseInsensitiveZipLoading == null)
			caseInsensitiveZipLoading = DefineUtil.getDefineBool('POLYMOD_ZIP_INSENSITIVE', true);
		return caseInsensitiveZipLoading;
	 }
}
