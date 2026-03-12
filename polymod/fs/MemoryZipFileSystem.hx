package polymod.fs;

// import format.zip.Reader;
import polymod.Polymod;
import polymod.fs.ZipFileSystem.ZipFileSystemParams;
import polymod.util.Util;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.Path;
import haxe.zip.Entry;
import haxe.zip.InflateImpl;

#if !html5
class MemoryZipFileSystem extends StubFileSystem
{
  public function new(params:ZipFileSystemParams)
  {
    super(params);
    Polymod.error(FUNCTIONALITY_NOT_IMPLEMENTED, "This file system not supported for this platform, and is only intended for use in html5");
  }

  public function addZipFile(zipName:String, zipBytes:Bytes)
  {
    Polymod.error(FUNCTIONALITY_NOT_IMPLEMENTED, "This file system not supported for this platform, and is only intended for use in html5");
  }
}
#else

/**
 * An implementation of an IFileSystem that can access files from an un-compressed zip archive.
 * Useful for loading mods from zip files.
 * Currently does not support compressed zip files. Recommended for use in html5 only.
 */
class MemoryZipFileSystem extends MemoryFileSystem
{
  var pathIsCompressed:Map<String, Bool>;

  public function new(params:ZipFileSystemParams)
  {
    super(params);
    pathIsCompressed = new Map();
  }

  #if debug
  /**
   * Prints the metadata of a ZIP file entry. Used for debugging.
   */
  function printEntry(e:haxe.zip.Entry)
  {
    Polymod.debug('
      datasize: ${e.dataSize},
      data: ${e.data.length},
      crc32: ${e.crc32},
      filename: ${e.fileName},
      filesize: ${e.fileSize}
      fileTime: ${e.fileTime},
      compressed: ${e.compressed},
      extraFields: ${e.extraFields.toString()}');
  }
  #end

  /**
   * Extracts the contents of a zip file (provided as bytes) and stores the contents in the MemoryFileSystem.
   *
   * @see https://github.com/HaxeFoundation/haxe.org-comments/issues/41#issuecomment-845576836
   */
  public function addZipFile(zipName:String, zipBytes:Bytes)
  {
    var bytesInput = new BytesInput(zipBytes);
    var reader = new haxe.zip.Reader(bytesInput);

    var modId = Path.withoutExtension(zipName);

    // Read the zip file entries.
    var entries:List<haxe.zip.Entry> = reader.read();
    for (zipEntry in entries)
    {
      var entryData = zipEntry.data; // we'll store the data in compressed form and decompress it when getFileBytes is called
      if (zipEntry.fileName.substring(zipEntry.fileName.lastIndexOf('/') + 1) == '' && zipEntry.data.toString() == '')
      {
        // This is a directory entry.
      }
      else
      {
        // This is a file entry! Register it in the MemoryFileSystem.
        var filePath = haxe.io.Path.join([this.modRoot, modId, zipEntry.fileName]);
        addFileBytes(filePath, entryData);
        pathIsCompressed.set(filePath, zipEntry.compressed);
      }
    }
  }

  override function getFileBytes(path:String):Bytes
  {
    var compressedBytes = super.getFileBytes(path);

    if (pathIsCompressed.get(path) != null && pathIsCompressed.get(path)) return Util.unzipBytes(compressedBytes);

    return compressedBytes; // if it wasn't actually compressed
  }

  @:deprecated("getMetadata is deprecated, use getMetadataByDir")
  public override function getMetadata(dirName:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return getMetadataByDir(dirName, origin);
  }

  public override function getMetadataByDir(dirName:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return super.getMetadataByDir(dirName, origin);
  }

  public override function getMetadataById(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return super.getMetadataById(modId, origin);
  }
}
#end
