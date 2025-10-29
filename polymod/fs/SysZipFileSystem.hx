package polymod.fs;

import polymod.fs.ZipFileSystem.ZipFileSystemParams;
#if !sys
class SysZipFileSystem extends polymod.fs.StubFileSystem
{
	public function new(params:ZipFileSystemParams)
	{
		super(params);
		Polymod.warning(FUNCTIONALITY_NOT_IMPLEMENTED, "This file system not supported for this platform, and is only intended for use on sys targets");
	}
}
#else
import haxe.Constraints.IMap;
import haxe.ds.StringMap;
import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod.ModMetadata;
import polymod.util.Util;
import polymod.util.InsensitiveMap;
import polymod.util.zip.ZipParser;
import sys.io.File;
import thx.semver.VersionRule;

using StringTools;
using polymod.util.Util;

/**
 * An implementation of an IFileSystem that can access mod files
 * from both directories AND ZIP archives in the mod root.
 *
 * Supports compressed and uncompressed ZIP files.
 * Compatible only with native targets.
 */
class SysZipFileSystem extends SysFileSystem
{
	/**
	 * Specifies the name of the ZIP that contains each file.
	 */
	var filesLocations:IMap<String, String>;

	/**
	 * Specifies the names of available directories within the ZIP files.
	 */
	var fileDirectories:Array<String>;

	/**
	 * The wrappers for each ZIP file that is loaded.
	 */
	var zipParsers:Map<String, ZipParser>;

	public function new(params:ZipFileSystemParams)
	{
		super(params);
		filesLocations = PolymodConfig.caseInsensitiveZipLoading ? new InsensitiveMap() : new StringMap();
		zipParsers = new Map<String, ZipParser>();
		fileDirectories = [];

		if (params.autoScan == null)
			params.autoScan = true;

		if (params.autoScan)
			addAllZips();
	}

	#if linux
	public override function getPathLike(path:String):Null<String> {
		var filePath = filesLocations.get(path);
		if (filePath != null) return path;

		var dirIdx = fileDirectories.indexOfInsens(path);
		if (dirIdx != -1) return fileDirectories[dirIdx];

		return super.getPathLike(path);
	}
	#end

	/**
	 * Retrieve file bytes by pulling them from the ZIP file.
	 */
	public override function getFileBytes(path:String):Null<Bytes>
	{
		path = Util.filterASCII(path);
		if (!filesLocations.exists(path))
		{
			// Fallback to the inner SysFileSystem.
			return super.getFileBytes(path);
		}
		else
		{
			// Rather than going to the `files` map for the contents (which are empty),
			// we go directly to the zip file and extract the individual file.

			// Determine which zip the target file is in.
			var zipPath = filesLocations.get(path);
			var zipParser = zipParsers.get(zipPath);
			var modId = Path.withoutExtension(Path.withoutDirectory(zipPath));

			var innerPath = path;
			// Remove mod root from path
			if (innerPath.startsWith(modRoot))
			{
				innerPath = innerPath.substring(modRoot.endsWith("/") ? modRoot.length : modRoot.length + 1);
			}
			// Remove mod ID from path
			if (innerPath.startsWith(modId))
			{
				innerPath = innerPath.substring(modId.length + 1);
			}

			var fileHeader = zipParser.getLocalFileHeaderOf(innerPath);
			if (fileHeader == null)
			{
				// Couldn't access file
				Polymod.debug('Could not access file $innerPath from ZIP ${zipParser.fileName}.');
				return null;
			}
			var fileBytes = fileHeader.readData();
			return fileBytes;
		}
	}

	public override function exists(path:String)
	{
		if (filesLocations.exists(path))
			return true;

		if (fileDirectories.containsInsens(path))
			return true;

		return super.exists(path);
	}

	public override function isDirectory(path:String)
	{
		if (fileDirectories.containsInsens(path))
			return true;

		if (filesLocations.exists(path))
			return false;

		return super.isDirectory(path);
	}

	public override function readDirectory(path:String):Array<String>
	{
		// Remove trailing slash
		if (path.endsWith("/"))
			path = path.substring(0, path.length - 1);

		var result = super.readDirectory(path);
		result = (result == null) ? [] : result;

		if (fileDirectories.containsInsens(path))
		{
			final insensitive:Bool = PolymodConfig.caseInsensitiveZipLoading;
			if (insensitive)
				path = path.toLowerCase();

			// We check if directory ==, because
			// we don't want to read the directory recursively.
			for (file in filesLocations.keys())
			{
				if (Path.directory(insensitive ? file.toLowerCase() : file) == path)
				{
					result.push(Path.withoutDirectory(file));
				}
			}
			for (dir in fileDirectories)
			{
				if (Path.directory(insensitive ? dir.toLowerCase() : dir) == path)
				{
					result.push(Path.withoutDirectory(dir));
				}
			}
		}

		return result;
	}

	/**
	 * Scan the mod root for ZIP files and add each one to the SysZipFileSystem.
	 */
	public function addAllZips():Void
	{
		Polymod.notice(MOD_LOAD_PREPARE, 'Searching for ZIP files in ' + modRoot);
		// Use SUPER because we don't want to add in files within the ZIPs.
		var modRootContents = super.readDirectory(modRoot);
		Polymod.notice(MOD_LOAD_PREPARE, 'Found ${modRootContents.length} files in modRoot.');

		for (modRootFile in modRootContents)
		{
			var filePath = Util.pathJoin(modRoot, modRootFile);

			// Skip directories.
			if (isDirectory(filePath))
				continue;

			// Only process ZIP files.
			if (StringTools.endsWith(filePath, ".zip"))
			{
				Polymod.notice(MOD_LOAD_PREPARE, '- Adding zip file: $filePath');
				addZipFile(filePath);
			}
		}
	}

	public function addZipFile(zipPath:String)
	{
		// Strip the path and extension to get the mod ID.
		var modId = Path.withoutExtension(Path.withoutDirectory(zipPath));

		var zipParser = new ZipParser(zipPath);

		// SysZipFileSystem doesn't actually use the internal `files` map.
		// We populate it here simply so we know the files are there.
		for (fileName => fileHeader in zipParser.centralDirectoryRecords)
		{
			// File is empty. Skip.
			if (fileHeader.compressedSize == 0 || fileHeader.uncompressedSize == 0)
				continue;

			// File is a directory. Skip.
			if (StringTools.endsWith(fileName, '/'))
				continue;

			// Add to the list of files.
			// The file should appear in the mod list as though it was in a directory rather than a ZIP.
			var fullFilePath = Path.join([modRoot, modId, fileHeader.fileName]);
			filesLocations.set(fullFilePath, zipPath);

			// Generate the list of directories.
			var fileDirectory = Path.directory(fullFilePath);
			// Resolving recursively ensures parent directories are registered.
			// If the directory is already registered, its parents are already registered as well.
			while (fileDirectory != "" && !fileDirectories.contains(fileDirectory))
			{
				fileDirectories.push(fileDirectory);
				fileDirectory = Path.directory(fileDirectory);
			}
		}

		// Store the ZIP parser for later use.
		zipParsers.set(zipPath, zipParser);
	}
}
#end
