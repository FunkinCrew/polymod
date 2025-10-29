package polymod.backends;

import haxe.io.Bytes;
import haxe.xml.Fast;
import haxe.xml.Printer;
import polymod.Polymod;
import polymod.Polymod.PolymodError;
import polymod.util.Util;
import polymod.backends.PolymodAssetLibrary;
import polymod.backends.PolymodAssets.PolymodAssetType;
#if unifill
import unifill.Unifill;
#end
#if heaps
import hxd.Res;
import hxd.res.Any;
import hxd.res.Loader;
import hxd.fs.FileEntry;
import hxd.fs.FileSystem;
import hxd.fs.LoadedBitmap;
import hxd.fs.LocalFileSystem;
import hxd.fs.BytesFileSystem.BytesFileEntry;
#end

#if !heaps
class HEAPSBackend extends StubBackend
{
	public function new()
	{
		super();
		Polymod.error(FAILED_CREATE_BACKEND, "HEAPSBackend requires the heaps library, did you forget to install it?");
	}
}
#else
class HEAPSBackend implements IBackend
{
	// STATIC:
	public static var defaultLoader:Loader = null;

	private static function getDefaultLoader()
	{
		if (defaultLoader == null)
		{
			var loader = Res.loader;
			if (Std.isOfType(loader, HEAPSModLoader) == false)
			{
				defaultLoader = loader;
			}
		}
		return defaultLoader;
	}

	private static function restoreDefaultLoader()
	{
		if (defaultLoader != null)
		{
			Res.loader = defaultLoader;
		}
	}

	// Instance:
	public var polymodLibrary:PolymodAssetLibrary;
	public var modLoader(default, null):HEAPSModLoader;
	public var fallback(default, null):Loader;

	public function new()
	{
	}

	public function init(?params:FrameworkParams):Bool
	{
		fallback = getDefaultLoader();
		modLoader = new HEAPSModLoader(this);
		Res.loader = modLoader;
		return true;
	}

	public function destroy()
	{
		restoreDefaultLoader();
		modLoader.destroy();
		modLoader = null;
		fallback = null;
		polymodLibrary = null;
	}

	public function exists(id:String):Bool
	{
		return modLoader.exists(id);
	}

	public function getBytes(id:String):Bytes
	{
		return modLoader.load(id).entry.getBytes();
	}

	public function getText(id:String):String
	{
		return modLoader.loadText(id).toText();
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
		if (defaultLoader != null)
		{
			defaultLoader.cleanCache();
		}
	}

	public function stripAssetsPrefix(id:String):String
	{
		return id;
	}
}

class HEAPSModLoader extends Loader
{
	var b:HEAPSBackend;
	var p:PolymodAssetLibrary;
	var fallback:Loader;
	var hasFallback:Bool;

	public function new(backend:HEAPSBackend)
	{
		b = backend;
		p = b.polymodLibrary;
		fallback = b.fallback;
		hasFallback = fallback != null;
		var fileSystem = new ModFileSystem(p);
		super(fileSystem);
	}

	public function destroy()
	{
		b = null;
		p = null;
		fallback = null;
	}

	public override function exists(path:String):Bool
	{
		var e = p.check(path);
		if (!e && hasFallback)
			return fallback.exists(path);
		return e;
	}

	public override function load(path:String):Any
	{
		if (p.getExtensionType(Util.uExtension(path)) == TEXT)
		{
			return loadText(path);
		}
		return loadBytes(path);
	}

	private function loadBytes(path:String):Any
	{
		var e = p.check(path);
		if (!e && hasFallback)
		{
			var result = fallback.load(path);
			return result;
		}
		return super.load(path);
	}

	public function loadText(path:String):Any
	{
		var modText = null;
		if (p.check(path))
		{
			modText = loadBytes(path).toText();
		}
		else if (hasFallback)
		{
			modText = fallback.load(path).toText();
		}

		if (modText != null)
		{
			modText = p.mergeAndAppendText(path, modText);
		}
		return new Any(this, new BytesFileEntry(path, Bytes.ofString(modText)));
	}
}

class ModFileEntry extends BytesFileEntry
{
	var fullFilePath:String;
	var fs:ModFileSystem;
	var p:PolymodAssetLibrary;
	var b:HEAPSBackend;
	var inited:Bool = false;

	public function new(path:String, bytes:Bytes, fs:ModFileSystem, fullFilePath:String)
	{
		this.fullFilePath = fullFilePath;
		this.fs = fs;
		p = fs.p;
		b = cast fs.b;
		super(path, bytes);
	}

	private function isPathADirectory(str:String)
	{
		if (p.fileSystem.exists(str) && p.fileSystem.isDirectory(str))
			return true;
		var entry = b.fallback.fs.get(str);
		if (entry != null && entry.isDirectory)
			return true;
		return false;
	}

	public override function iterator():hxd.impl.ArrayIterator<FileEntry>
	{
		var arr:Array<FileEntry> = [];

		var otherList = [];
		var fallbackEntry = b.fallback.fs.get(fullFilePath);
		for (otherEntry in fallbackEntry.iterator())
		{
			otherList.push(otherEntry);
		}

		var isDir = isPathADirectory(path);
		var dirPath = isDir ? path : Util.uPathPop(fullFilePath);

		var itemPaths = [];
		for (id in p.type.keys())
		{
			if (id.indexOf(dirPath) != 0)
				continue;
			if (Util.isMergeOrAppend(id))
				continue;
			if (p.ignoredFiles.indexOf(id) != -1)
				continue;
			if (p.fileSystem.isDirectory(id))
				continue;
			arr.push(new ModFileEntry(id, null, fs, id));
			itemPaths.push(id);
		}

		for (otherEntry in otherList)
		{
			if (itemPaths.indexOf(otherEntry.path) == -1)
			{
				var otherPath = otherEntry.path;
				var nextPath = Util.pathJoin(fullFilePath, otherPath);
				arr.push(new ModFileEntry(otherPath, null, fs, nextPath));
			}
		}

		return new hxd.impl.ArrayIterator(arr);
	}

	public override function get(name:String):FileEntry
	{
		var nextPath = Util.pathJoin(fullFilePath, name);
		return new ModFileEntry(name, null, fs, nextPath);
	}

	private inline function initBytes()
	{
		if (inited == false && bytes == null)
		{
			resolveBytes();
			inited = true;
		}
	}

	private function resolveBytes()
	{
		var file = p.file(path);
		bytes = p.fileSystem.getFileBytes(file);
		if (bytes == null)
		{
			var entry = b.fallback.fs.get(path);
			bytes = entry.getBytes();
		}
	}

	override function getSign():Int
	{
		initBytes();
		return super.getSign();
	}

	override function getBytes():Bytes
	{
		initBytes();
		return super.getBytes();
	}

	override function readByte():Int
	{
		initBytes();
		return super.readByte();
	}

	override function read(out:Bytes, pos:Int, size:Int)
	{
		initBytes();
		return super.read(out, pos, size);
	}

	override function loadBitmap(onLoaded:LoadedBitmap->Void):Void
	{
		initBytes();
		return super.loadBitmap(onLoaded);
	}

	override function get_size()
	{
		initBytes();
		return super.get_size();
	}
}

class ModFileSystem implements FileSystem
{
	public var p:PolymodAssetLibrary;
	public var b:HEAPSBackend;

	public function new(polymodAssetLibrary:PolymodAssetLibrary)
	{
		p = polymodAssetLibrary;
		b = cast p.backend;
	}

	public function getRoot():FileEntry
	{
		return new ModFileEntry('', null, this, '');
	}

	public function get(path:String):FileEntry
	{
		var file = p.file(path);
		var bytes = p.fileSystem.getFileBytes(file);
		if (bytes == null)
		{
			var entry = b.fallback.fs.get(path);
			return entry;
		}
		var modEntry = new ModFileEntry(path, bytes, this, path);
		return modEntry;
	}

	public function exists(path:String):Bool
	{
		return b.modLoader.exists(path);
	}

	public function dispose():Void
	{
		p = null;
		b = null;
	}

	public function dir(path:String):Array<FileEntry>
	{
		var names = p.fileSystem.readDirectory(path);
		var arr = [];
		for (name in names)
		{
			arr.push(get(name));
		}
		return arr;
	}
}
#end
