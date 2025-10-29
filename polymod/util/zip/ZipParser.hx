package polymod.util.zip;

#if sys
import haxe.Constraints.IMap;
import haxe.ds.StringMap;
import haxe.io.Bytes;
import polymod.util.InsensitiveMap;
import sys.io.File;
import sys.io.FileInput;

/**
 * Parses the Central Directory Headers of a ZIP file on the file system.
 * This allows individual files to be directly accessed without having to
 * decompress the entire ZIP file.
 * 
 * Only compatible with `sys` targets with native file system access.
 */
class ZipParser
{
	/**
	 * The file system path to the ZIP file.
	 */
	public var fileName:String;

	/**
	 * A handle to the ZIP file for direct reading.
	 */
	private var fileHandle:FileInput;

	/**
	 * The end-of-central-directory record, as parsed from the end of the ZIP file.
	 */
	public var endOfCentralDirectoryRecord:EndOfCentralDirectoryRecord;

	/**
	 * The central directory records, as parsed from the central directory.
	 * These contain metadata about each file in the archive.
	 */
	public var centralDirectoryRecords:IMap<String, CentralDirectoryFileHeader>;

	public function new(fileName:String)
	{
		this.fileName = fileName;
		this.fileHandle = File.read(this.fileName);

		findEndOfCentralDirectoryRecord();
		getAllCentralDirectoryHeaders();
	}

	/**
	 * Locate the end-of-central-directory record in the ZIP file.
	 */
	function findEndOfCentralDirectoryRecord():Void
	{
		fileHandle.seek(-22, SeekEnd); // 22 is the smallest the eocd can be, so we start here
		var tmpbuf = Bytes.alloc(4);
		fileHandle.readBytes(tmpbuf, 0, 4);
		// keep sliding backwards until we find a signature match (dunno if this is the best way to do this but it works)
		while (tmpbuf.getInt32(0) != EndOfCentralDirectoryRecord.SIGNATURE)
		{
			fileHandle.seek(-5, SeekCur);
			fileHandle.readBytes(tmpbuf, 0, 4);
		}
		this.endOfCentralDirectoryRecord = new EndOfCentralDirectoryRecord(fileHandle, -4);
	}

	/**
	 * Read all the central directory headers from the ZIP file.
	 * This can be used to get metadata about each file in the archive.
	 */
	function getAllCentralDirectoryHeaders():Void
	{
		this.centralDirectoryRecords = PolymodConfig.caseInsensitiveZipLoading ? new InsensitiveMap() : new StringMap();
		fileHandle.seek(this.endOfCentralDirectoryRecord.cdrOffset, SeekBegin);
		for (_ in 0...this.endOfCentralDirectoryRecord.cdrsTotal)
		{
			var cdh = new CentralDirectoryFileHeader(fileHandle);
			this.centralDirectoryRecords.set(cdh.fileName, cdh);
		}
	}

	/**
	 * Read the centeral directory header for a specific file,
	 * and generate a LocalFileHeader.
	 * 
	 * @param localFileName A filename relative to the root of the ZIP file.
	 * @return A LocalFileHeader for the specified file, or null if the file was not found.
	 */
	public function getLocalFileHeaderOf(localFileName:String):LocalFileHeader
	{
		fileHandle = File.read(this.fileName);
		var cdfh = centralDirectoryRecords.get(localFileName);
		if (cdfh == null)
		{
			Polymod.warning(FILE_MISSING, 'The file $localFileName was not found in the zip: $fileName');
			return null;
		}
		fileHandle.seek(cdfh.localFileHeaderOffset, SeekBegin);
		var lfh = new LocalFileHeader(fileHandle);
		lfh.dataOffset = fileHandle.tell();
		return lfh;
	}
}

enum CompressionMethod
{
	NONE;
	DEFLATE;
}

/**
 * Common functionality for all ZIP headers.
 */
private class Header
{
	/**
	 * A handle to the ZIP file for direct reading.
	 */
	private var fileInput:FileInput;

	/**
	 * The header's 4-byte signature.
	 */
	public var signature:Bytes;

	/**
	 * A temporary buffer to read chunks of bytes into.
	 */
	private var tmpBuffer:Bytes;

	/**
	 * Reads a chunk of bytes of the specified length from the file,
	 * then advances the file pointer.
	 * 
	 * @param count The number of bytes to read.
	 * @return A Bytes object containing the read bytes.
	 */
	private function getBytesFromFile(count:Int)
	{
		if (count == 0)
			return Bytes.alloc(0);
		tmpBuffer = Bytes.alloc(count);
		var bytesRead = fileInput.readBytes(tmpBuffer, 0, count);
		if (bytesRead != count)
		{
			Polymod.debug('Read fewer bytes than requested ($bytesRead < $count)');
		}
		return tmpBuffer;
	}

	/**
	 * Parses a `lastModifiedDate` and `lastModifiedTime`, in MSDOS date format,
	 * into a Haxe `Date` object.
	 * 
	 * @param lastModifiedTime 
	 * @param lastModifiedDate 
	 * @return A `Date` object representing the parsed date.
	 */
	function parseMSDOSDate(lastModifiedTime:Bytes, lastModifiedDate:Bytes)
	{
		var timeNum:Int = lastModifiedTime.getUInt16(0);
		var bits_0to4 = timeNum & 0x1F;
		var bits_5to10 = (timeNum >> 5) & 0x3F;
		var bits_11to15 = (timeNum >> 11) & 0x1F;

		var hours:Int = bits_11to15 % 24;
		var minutes:Int = bits_5to10 % 60;
		var seconds:Int = bits_0to4 * 2;

		var dateNum:Int = lastModifiedDate.getUInt16(0);
		bits_0to4 = dateNum & 0x1F;
		var bits_5to8 = (dateNum >> 5) & 0xF;
		var bits_9to15 = (dateNum >> 9);

		var year = 1980 + bits_9to15;
		var month = (bits_5to8 - 1) % 12;
		var date = bits_0to4 % 31;

		return new Date(year, month, date, hours, minutes, seconds);
	}
}

/**
 * The local file header for a file in a ZIP file.
 */
class LocalFileHeader extends Header
{
	/**
	 * Local file header signature = 0x04034b50 (PK♥♦ or "PK\3\4") 
	 */
	public static final HEADER_SIGNATURE = 0x04034B50;

	/**
	 * Version needed to extract (minimum) 
	 */
	public var minVersionForExtraction:Int;

	/**
	 * General purpose bit flag 
	 */
	public var generalPurposeBitFlag:Bytes;

	/**
	 * Compression method; e.g. none = 0, DEFLATE = 8 (or "\0x08\0x00")
	 * Converted to a Haxe enum.
	 */
	public var compressionMethod:CompressionMethod;

	/**
	 * Date and time of last modification, parsed from MSDOS format.
	 */
	public var lastModifiedDateTime:Date;

	/**
	 * CRC-32 of uncompressed data 
	 */
	public var crc32code:Bytes;

	/**
	 * Compressed size (or 0xffffffff for ZIP64) 
	 */
	public var compressedSize:Int;

	/**
	 * Uncompressed size (or 0xffffffff for ZIP64) 
	 */
	public var uncompressedSize:Int;

	/**
	 * ZIP filename
	 */
	public var fileName:String;

	/**
	 * ZIP extra field 
	 */
	public var extraField:Bytes;

	/**
	 * Number of bytes consumed when reading the header.
	 */
	public var bytesConsumed:Int;

	/**
	 * Byte offset in the file from where to read the data.
	 * Populated by `getLocalFileHeaderOf` after the header is read.
	 */
	public var dataOffset:Int = -1; // offset in the file from where to read the data

	public function new(fileInput:FileInput, ?startOffset:Int = 0)
	{
		this.fileInput = fileInput;
		this.fileInput.seek(startOffset, SeekCur);

		// These fields are being read in the order they are defined in the spec.

		signature = getBytesFromFile(4);

		minVersionForExtraction = getBytesFromFile(2).getUInt16(0);
		generalPurposeBitFlag = getBytesFromFile(2);
		compressionMethod = (getBytesFromFile(2).getUInt16(0) == 0) ? NONE : DEFLATE;

		var lastModifiedTime = getBytesFromFile(2);
		var lastModifiedDate = getBytesFromFile(2);
		lastModifiedDateTime = parseMSDOSDate(lastModifiedTime, lastModifiedDate);

		crc32code = getBytesFromFile(4);

		compressedSize = getBytesFromFile(4).getInt32(0);
		uncompressedSize = getBytesFromFile(4).getInt32(0);

		var fileNameLength = getBytesFromFile(2);
		var extraFieldLength = getBytesFromFile(2);

		fileName = getBytesFromFile(fileNameLength.getUInt16(0)).toString();

		extraField = getBytesFromFile(extraFieldLength.getUInt16(0));

		bytesConsumed = 30 + fileNameLength.getUInt16(0) + extraFieldLength.getUInt16(0) - 1;
	}

	/**
	 * Reads the bytes of the local file from the input ZIP it is associated with,
	 * decompressing them if necessary.
	 * 
	 * @return The bytes of the local file.
	 */
	public function readData():Bytes
	{
		fileInput.seek(dataOffset, SeekBegin);
		var bytesBuf = new haxe.io.BytesBuffer();

		var bytesToReturn = Bytes.alloc(compressedSize);
		var bytesRead = fileInput.readBytes(bytesToReturn, 0, compressedSize);

		if (bytesRead < compressedSize)
		{
			// trace('[WARNING] Bytes read was fewer than requested (Requested: $compressedSize, Read: $bytesRead)');
			bytesBuf.addBytes(bytesToReturn, 0, bytesRead);
			while (bytesRead < compressedSize)
			{
				bytesRead += fileInput.readBytes(bytesToReturn, 0, compressedSize - bytesRead);
				bytesBuf.addBytes(bytesToReturn, 0, compressedSize - bytesRead);
			}
			return (this.compressionMethod == DEFLATE) ? Util.unzipBytes(bytesBuf.getBytes()) : bytesBuf.getBytes();
		}

		return (this.compressionMethod == DEFLATE) ? Util.unzipBytes(bytesToReturn) : bytesToReturn;
	}

	/**
	 * Determine if the header is valid by checking the signature.
	 */
	public function isValid()
	{
		return signature.getInt32(0) == HEADER_SIGNATURE; // Std.parseInt(HEADER_SIGNATURE);
	}

	public function toString()
	{
		return '
        signature: ${signature.toHex()}
        minimum version to extract: $minVersionForExtraction
        general purpose bit flags: ${generalPurposeBitFlag.toHex()}
        compression method: $compressionMethod
        last modified date: $lastModifiedDateTime
        crc32: $crc32code
        compressed size: $compressedSize
        uncompressed size: $uncompressedSize
        file name: $fileName
        extra field bits: ${extraField.toHex()}
        bytes consumed: $bytesConsumed
        ';
	}
}

/**
 * The central directory file header for a file in a ZIP file.
 */
 class CentralDirectoryFileHeader extends Header
 {
	/**
	 * Central directory file header signature = 0x02014b50 
	 */
	public static final HEADER_SIGNATURE = 0x02014B50;

	/**
	 * Version made by
	 */
	public var versionMadeBy:Int;

	/**
	 * Version needed to extract (minimum)
	 */
	public var versionToExtract:Int;

	/**
	 * General purpose bit flag
	 */
	private var generalPurposeBitFlag:Bytes;

	/**
	 * Compression method (none or deflate)
	 */
	public var compressionMethod:CompressionMethod;

	/**
	 * Last modified date and time, parsed from MSDOS format
	 */
	public var lastModifiedDateTime:Date;

	/**
	 * CRC-32 of uncompressed data 
	 */
	private var crc32code:Bytes;

	/**
	 * Compressed size (or 0xffffffff for ZIP64) 
	 */
	public var compressedSize:Int;

	/**
	 * Uncompressed size (or 0xffffffff for ZIP64) 
	 */
	public var uncompressedSize:Int;

	/**
	 * File name length
	 */
	private var fileNameLength:Int;

	/**
	 * Extra field length
	 */
	private var extraFieldLength:Int;

	/**
	 * File comment length
	 */
	private var fileCommentLength:Int;

	/**
	 * Disk number where file starts (or 0xffff for ZIP64) 
	 */
	public var diskNumber:Int;

	/**
	 * Internal file attributes
	 */
	private var internalFileAttrib:Bytes;

	/**
	 * External file attributes
	 */
	private var externalFileAttrib:Bytes;

	/**
	 * Relative offset of local file header (or 0xffffffff for ZIP64).
	 * This is the number of bytes between the start of the first disk on which the file occurs,
	 * and the start of the local file header.
	 * This allows software reading the central directory to locate the position of the file inside the ZIP file. 
	 */
	public var localFileHeaderOffset:Int;

	/**
	 * File name
	 */
	public var fileName:String;

	/**
	 * Extra field
	 */
	public var extraField:Bytes;

	/**
	 * File comment
	 */
	public var fileComment:String;

	/**
	 * Number of bytes consumed by this header.
	 */
	public var bytesConsumed:Int;

	public function new(fileInput:FileInput, ?startOffset:Int = 0)
	{
		this.fileInput = fileInput;
		this.fileInput.seek(startOffset, SeekCur);

		// These fields are being read in the order they are defined in the spec.

		signature = getBytesFromFile(4);
		versionMadeBy = getBytesFromFile(2).getUInt16(0);
		versionToExtract = getBytesFromFile(2).getUInt16(0);
		generalPurposeBitFlag = getBytesFromFile(2);
		compressionMethod = (getBytesFromFile(2).getUInt16(0) == 0) ? NONE : DEFLATE;

		var lastModifiedTime = getBytesFromFile(2);
		var lastModifiedDate = getBytesFromFile(2);
		lastModifiedDateTime = parseMSDOSDate(lastModifiedTime, lastModifiedDate);

		crc32code = getBytesFromFile(4);
		compressedSize = getBytesFromFile(4).getInt32(0);
		uncompressedSize = getBytesFromFile(4).getInt32(0);

		fileNameLength = getBytesFromFile(2).getUInt16(0);
		extraFieldLength = getBytesFromFile(2).getUInt16(0);
		fileCommentLength = getBytesFromFile(2).getUInt16(0);

		diskNumber = getBytesFromFile(2).getUInt16(0);
		internalFileAttrib = getBytesFromFile(2);
		externalFileAttrib = getBytesFromFile(4);
		localFileHeaderOffset = getBytesFromFile(4).getInt32(0);

		fileName = getBytesFromFile(fileNameLength).toString();
		extraField = getBytesFromFile(extraFieldLength);
		fileComment = getBytesFromFile(fileCommentLength).toString();

		bytesConsumed = 46 + fileNameLength + extraFieldLength + fileCommentLength - 1;
	}

	/**
	 * Validate the header signature matches the expected value.
	 */
	public function isValid()
	{
		return signature.getInt32(0) == HEADER_SIGNATURE;
	}

	public function toString()
	{
		return '
        version made by: $versionMadeBy
        version to extract: $versionToExtract
        general purpose bit flags: ${generalPurposeBitFlag.toHex()}
        compression method: $compressionMethod
        last modified date: $lastModifiedDateTime
        crc32: ${crc32code.toHex()}
        compressed size: $compressedSize
        uncompressed size: $uncompressedSize
        disk number: $diskNumber
        internal file attribute: ${internalFileAttrib.toHex()}
        external file attribute: ${externalFileAttrib.toHex()}
        local file header offset: $localFileHeaderOffset
        file name: $fileName
        extra field length (in hex): 0x${StringTools.hex(extraFieldLength)}
        extra field: 0x${extraField.toHex()}
        file comment: $fileComment
        bytes consumed: $bytesConsumed
        ';
	}
}

/**
 * The end of central directory record for a ZIP file.
 * Provides information like how many central directory records are present in the file,
 * and where the central directory is located.
 */
class EndOfCentralDirectoryRecord extends Header
{
	/**
	 * End of central directory signature = 0x06054b50 
	 */
	public static final SIGNATURE = 0x06054B50;

	/**
	 * Number of this disk (or 0xffff for ZIP64) 
	 */
	public var diskNumber:Int;
	/**
	 * Disk where central directory starts (or 0xffff for ZIP64) 
	 */
	public var startDisk:Int;
	/**
	 * Number of central directory records on this disk (or 0xffff for ZIP64) 
	 */
	public var cdrsOnDisk:Int;
	/**
	 * Total number of central directory records (i.e. the number of files) (or 0xffff for ZIP64)
	 */
	public var cdrsTotal:Int;
	/**
	 * Size of central directory (bytes) (or 0xffffffff for ZIP64) 
	 */
	public var cdrSize:Int;
	/**
	 * Offset of start of central directory, relative to start of archive (or 0xffffffff for ZIP64)
	 */
	public var cdrOffset:Int;

	/**
	 * Length of the comment string, in bytes.
	 */
	private var commentLength:Int;
	/**
	 * Comment string.
	 */
	public var comment:String;

	public function new(fileInput:FileInput, ?startOffset:Int = 0)
	{
		this.fileInput = fileInput;
		this.fileInput.seek(startOffset, SeekCur);

		// These fields are being read in the order they are defined in the spec.

		signature = getBytesFromFile(4);

		diskNumber = getBytesFromFile(2).getUInt16(0); // 0xffff = 65535
		startDisk = getBytesFromFile(2).getUInt16(0);
		cdrsOnDisk = getBytesFromFile(2).getUInt16(0);
		cdrsTotal = getBytesFromFile(2).getUInt16(0);

		cdrSize = getBytesFromFile(4).getInt32(0);
		cdrOffset = getBytesFromFile(4).getInt32(0);

		commentLength = getBytesFromFile(2).getUInt16(0);

		comment = getBytesFromFile(commentLength).toString();
	}

	public function toString()
	{
		return '
	        signature: ${signature.toHex()} | ${signature.getInt32(0)}
	        disk #: $diskNumber
	        CDR start disk #: $startDisk
	        # of CDRs on disk: $cdrsOnDisk
	        # of CDRs total: $cdrSize
	        CDR offset: $cdrOffset
	        comment: $comment';
	}
}
#end
