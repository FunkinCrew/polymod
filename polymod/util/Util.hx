package polymod.util;

import haxe.Utf8;
import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod.PolymodError;
import polymod.Polymod.PolymodErrorType;
import polymod.Polymod;
import polymod.format.BaseParseFormat;
import polymod.format.CSV;
import polymod.format.ParseRules.CSVParseFormat;
import polymod.format.ParseRules.TextFileFormat;
import polymod.format.ParseRules;
import polymod.fs.PolymodFileSystem.IFileSystem;
#if unifill
import unifill.Unifill;
#end

class Util
{
	/**
	 * For a given file, return a list of all its parent directories.
	 * @param filePath
	 * @return Array<String>
	 */
	public static function listAllParentDirs(filePath:String):Array<String>
	{
		var parentDirs:Array<String> = new Array<String>();
		var parentDir:String = filePath;
		while (parentDir != null && parentDir != "")
		{
			parentDirs.push(parentDir);
			parentDir = Path.directory(parentDir);

			// Prevent infinite loop
			if (parentDirs.contains(parentDir))
				parentDir = null;
		}
		return parentDirs;
	}

	public static inline function isMergeOrAppend(id:String):Bool
	{
		return uIndexOf(id, PolymodConfig.mergeFolder) == 0 || uIndexOf(id, PolymodConfig.appendFolder) == 0;
	}

	public static function mergeAndAppendText(baseText:String, id:String, dirs:Array<String>, getModText:String->String->String, fileSystem:IFileSystem,
			parseRules:ParseRules = null):String
	{
		var text = baseText;

		for (d in dirs)
		{
			if (fileSystem.exists(pathMerge(id, d)))
			{
				text = mergeText(text, id, d, getModText, parseRules);
			}
			if (fileSystem.exists(pathAppend(id, d)))
			{
				text = appendText(text, id, d, getModText, parseRules);
			}
		}

		return text;
	}

	/**
	 * Filters a unicode string to only contain characters that are valid in a filename.
	 */
	public static function filterASCII(str:String):String
	{
		var filtered:String = "";
		for (i in 0...str.length)
		{
			var c = str.charCodeAt(i);
			if (c >= 32 && c <= 126)
			{
				filtered += str.charAt(i);
			}
		}
		return filtered;
	}

	/**
	 * Looks for a '_merge' entry for an asset and tries to merge its contents into the original
	 * With the following rules:
	 * - Only applies to XML, TSV, and CSV files (identified by extension)
	 * - Adds single nodes from the merged asset into the original
	 * - If the original has that node too, it overwrites the original information
	 * @param	baseText	the basic text file you're merging extra content into
	 * @param	id	the name of the asset file
	 * @param	getModText	a function for getting the mod's contribution
	 * @param	mergeRules	formatting rules to help with merging
	 * @return
	 */
	public static function mergeText(baseText:String, id:String, theDir:String = '', getModText:String->String->String, parseRules:ParseRules = null):String
	{
		var extension = uExtension(id, true);
		id = stripPrefix(id);
		var mergeFile = PolymodConfig.mergeFolder + sl() + id;
		// try the path first
		var format:BaseParseFormat = parseRules.get(id);
		if (format == null)
		{
			// try the extension then
			format = parseRules.get(extension);
		}
		if (format != null)
		{
			var mergeText = getModText(mergeFile, theDir);
			return format.merge(baseText, mergeText, id);
		}
		else
		{
			Polymod.error(MERGE, "Could not merge file (" + id + "), no parse format was specified for extension (" + extension + ").");
			return baseText;
		}
		return baseText;
	}

	public static function appendText(baseText:String, id:String, theDir:String, getModText:String->String->String, parseRules:ParseRules = null):String
	{
		var extension = uExtension(id, true);
		id = stripPrefix(id);
		// try the path first
		var format:BaseParseFormat = parseRules.get(id);
		if (format == null)
		{
			// try the extension then
			format = parseRules.get(extension);
		}
		if (format != null)
		{
			var appendText = getModText(Util.pathJoin(PolymodConfig.appendFolder, id), theDir);
			return format.append(baseText, appendText, id);
		}
		return baseText;
	}

	public static function appendCSVOrTSV(baseText:String, appendText:String, id:String)
	{
		var lastChar = uCharAt(baseText, uLength(baseText) - 1);
		var lastLastChar = uCharAt(baseText, uLength(baseText) - 1);
		var joiner = '';
		var endLine = "\n";
		var crIndex = uIndexOf(baseText, "\r");
		var lfIndex = uIndexOf(baseText, "\n");

		if (crIndex != -1 && lfIndex == crIndex + 1)
		{
			endLine = "\r\n";
		}

		if (lastChar != "\n")
		{
			joiner = endLine;
		}

		var otherEndline = endLine == '\n' ? '\r\n' : '\n';
		appendText = uSplitReplace(appendText, otherEndline, endLine);

		return uCombine([baseText, joiner, appendText]);
	}

	public static function appendSpecialXML(a:String, b:String, headers:Array<String>, footers:Array<String>):String
	{
		a = stripXML(a, true, true, headers, footers);
		b = stripXML(b, true, true, headers, footers);

		var txt = '<?xml version="1.0" encoding="utf-8" ?>';
		txt = uCat(txt, "<data>");
		txt = uCat(txt, a);
		txt = uCat(txt, b);
		txt = uCat(txt, "</data>");

		return txt;
	}

	public static function appendXML(a:String, b:String):String
	{
		a = stripXML(a, false, true);
		b = stripXML(b, true, false);

		var txt = uCat(a, b);

		return txt;
	}

	public static function stripComments(txt:String):String
	{
		var start = uIndexOf(txt, "<!--");
		var end = uIndexOf(txt, "-->");
		while (start != -1 && end != -1)
		{
			var len = uLength(txt);
			var before = uSubstr(txt, 0, start);
			var after = uSubstr(txt, end + 3, len - (end + 3));
			txt = uCat(before, after);
			start = uIndexOf(txt, "<!--");
			end = uIndexOf(txt, "-->");
		}
		return txt;
	}

	public static function stripPathPrefix(value:String, prefix:String):String
	{
		var result = value;
		if (result.indexOf(prefix) == 0)
			result = result.substr(prefix.length);

		if (result.indexOf('/') == 0)
			result = result.substr(1);

		return result;
	}

	public static function trimLeadingWhiteSpace(txt:String):String
	{
		var white = ["\r", "\n", ' ', "\t"];
		var len = uLength(txt);
		for (w in white)
		{
			while (uIndexOf(txt, w) == 0)
			{
				txt = uSubstr(txt, 1, len - 1);
				len--;
			}
		}
		return txt;
	}

	public static function trimTrailingWhiteSpace(txt:String):String
	{
		var white = ["\r", "\n", ' ', "\t"];
		var len = uLength(txt);
		for (w in white)
		{
			while (uCharAt(txt, len - 1) == w)
			{
				txt = uSubstr(txt, 0, len - 1);
				len--;
			}
		}
		return txt;
	}

	public static function stripXML(txt:String, stripHeader:Bool = true, stripFooter:Bool = true, headers:Array<String> = null,
			footers:Array<String> = null):String
	{
		txt = stripComments(txt);

		if (stripHeader)
		{
			if (uIndexOf(txt, "<?xml") == 0)
			{
				var i = uIndexOf(txt, '>');
				txt = uSubstr(txt, i + 1, uLength(txt) - (i + 1));
				txt = trimLeadingWhiteSpace(txt);
			}
			if (uIndexOf(txt, "<data") == 0)
			{
				var i = uIndexOf(txt, '>');
				txt = uSubstr(txt, i + 1, uLength(txt) - (i + 1));
				txt = trimLeadingWhiteSpace(txt);
			}
			if (headers != null)
			{
				for (header in headers)
				{
					if (uIndexOf(txt, header) == 0)
					{
						var i = uIndexOf(txt, '>');
						txt = uSubstr(txt, (i + 1), uLength(txt) - (i + 1));
						txt = trimLeadingWhiteSpace(txt);
					}
				}
			}
		}
		if (stripFooter)
		{
			txt = trimTrailingWhiteSpace(txt);
			var ulen = uLength(txt);
			if (uLastIndexOf(txt, "</data>") == ulen - 7)
			{
				txt = uSubstr(txt, 0, ulen - 7);
			}
			if (footers != null)
			{
				for (footer in footers)
				{
					txt = trimTrailingWhiteSpace(txt);
					var ulen = uLength(txt);
					var footerlen = uLength(footer);
					if (uLastIndexOf(txt, footer) == ulen - footerlen)
					{
						txt = uSubstr(txt, 0, ulen - footerlen);
					}
				}
			}
		}
		return txt;
	}

	public static inline function pathMerge(id:String, theDir:String = ''):String
	{
		return pathSpecial(id, PolymodConfig.mergeFolder, theDir);
	}

	private static inline function pathAppend(id:String, theDir:String = ''):String
	{
		return pathSpecial(id, PolymodConfig.appendFolder, theDir);
	}

	public static inline function stripPrefix(id:String, prefix:String = 'assets/'):String
	{
		if (uIndexOf(id, prefix) == 0)
		{
			id = uSubstring(id, 7);
		}
		return id;
	}

	public static function pathSpecial(id:String, special:String = '', theDir:String = ''):String
	{
		#if (sys || nodefs || html5)
		id = stripPrefix(id);
		var thePath = uCombine([theDir, sl(), special, sl(), id]);
		return thePath;
		#else
		return '';
		#end
	}

	public static function pathJoin(a:String, b:String):String
	{
		var aSlash = (uLastIndexOf(a, '/') == uLength(a) - 1 || uLastIndexOf(a, '\\') == uLength(a) - 1);
		var bSlash = (uIndexOf(b, '/') == 0 || uIndexOf(b, '\\') == 0);
		var str = '';
		if (aSlash || bSlash)
		{
			str = Util.uCombine([a, b]);
		}
		else
		{
			str = Util.uCombine([a, sl(), b]);
		}
		str = cleanSlashes(str);
		return str;
	}

	public static function cleanSlashes(str:String):String
	{
		str = uSplitReplace(str, '\\', '/');
		str = uSplitReplace(str, '//', '/');
		return str;
	}

	public static function withTrailingSlash(str:String):String {
		var result = cleanSlashes(str);

		if (uLastIndexOf(result, '/') != uLength(result) - 1) {
			result += '/';
		}

		return result;
	}

	public static inline function sl():String
	{
		return '/';
	}

	@:access(haxe.xml.Xml)
	public static inline function copyXml(data:Xml, parent:Xml = null):Xml
	{
		var c:Xml = null;
		if (data.nodeType == Xml.Element)
		{
			c = Xml.createElement(data.nodeName);
			for (att in data.attributes())
			{
				c.set(att, data.get(att));
			}
			for (el in data.elements())
			{
				c.addChild(copyXml(el, c));
			}
		}
		else if (data.nodeType == Xml.PCData)
		{
			c = Xml.createPCData(data.nodeValue);
		}
		else if (data.nodeType == Xml.CData)
		{
			c = Xml.createCData(data.nodeValue);
		}
		else if (data.nodeType == Xml.Comment)
		{
			c = Xml.createComment(data.nodeValue);
		}
		else if (data.nodeType == Xml.DocType)
		{
			c = Xml.createDocType(data.nodeValue);
		}
		else if (data.nodeType == Xml.ProcessingInstruction)
		{
			c = Xml.createProcessingInstruction(data.nodeValue);
		}
		else if (data.nodeType == Xml.Document)
		{
			c = Xml.createDocument();
			for (el in data.elements())
			{
				c.addChild(copyXml(el, c));
			}
		}
		@:privateAccess c.parent = parent;
		return c;
	}

	/**
	 * Runs the 'Inflate' decompression algorithm on the raw compressed bytes
	 * and returns the uncompressed data.
	 *
	 * @param bytes A raw block of compressed bytes
	 * @return A raw block of uncompressed bytes
	 */
	public static function unzipBytes(compressedBytes:Bytes)
	{
		var returnBuf = new haxe.io.BytesBuffer();

		// Initialize the Inflate algorithm.
		var bytesInput = new haxe.io.BytesInput(compressedBytes);
		var inflater = new haxe.zip.InflateImpl(bytesInput, false, false);

		// Read and inflate the bytes in chunks of 65,535 bytes.
		var unzipBuf = Bytes.alloc(65535);
		var bytesRead = inflater.readBytes(unzipBuf, 0, unzipBuf.length);
		while (bytesRead == unzipBuf.length)
		{
			returnBuf.addBytes(unzipBuf, 0, bytesRead);
			bytesRead = inflater.readBytes(unzipBuf, 0, unzipBuf.length);
		}
		// Add the last chunk of bytes to the return buffer.
		returnBuf.addBytes(unzipBuf, 0, bytesRead);

		// Return the uncompressed bytes.
		return returnBuf.getBytes();
	}

	/**
	 * String concatenation	with UTF-8 compatibility.
	 * @param a
	 * @param b
	 * @return String
	 */
	public static function uCat(a:String, b:String):String
	{
		var sb = new StringBuf();
		sb.add(Std.string(a));
		sb.add(Std.string(b));
		return sb.toString();
	}

	public static function uCharAt(str:String, index:Int):String
	{
		#if unifill
		return Unifill.uCharAt(str, index);
		#else
		return str.charAt(index);
		#end
	}

	public static function uJoin(arr:Array<String>, token:String):String
	{
		var sb = new StringBuf();
		var i = 0;
		for (str in arr)
		{
			sb.add(str);
			if (i != arr.length - 1)
			{
				sb.add(token);
			}
			i++;
		}
		return sb.toString();
	}

	public static function uCombine(arr:Array<String>):String
	{
		var sb = new StringBuf();
		for (str in arr)
		{
			sb.add(str);
		}
		return sb.toString();
	}

	public static function uExtension(str:String, lowerCase:Bool = false):String
	{
		var i = uLastIndexOf(str, '.');
		var extension = uSubstr(str, i + 1, uLength(str) - (i + 1));
		if (lowerCase)
		{
			extension = extension.toLowerCase();
		}
		return extension;
	}

	public static inline function uIndexOf(str:String, substr:String, ?startIndex:Int):Int
	{
		#if unifill
		return Unifill.uIndexOf(str, substr, startIndex);
		#else
		return str.indexOf(substr, startIndex);
		#end
	}

	public static inline function uLastIndexOf(str:String, value:String, ?startIndex:Int):Int
	{
		#if unifill
		return Unifill.uLastIndexOf(str, value, startIndex);
		#else
		return str.lastIndexOf(value, startIndex);
		#end
	}

	public static inline function uLength(str:String):Int
	{
		#if unifill
		return Unifill.uLength(str);
		#else
		return str.length;
		#end
	}

	public static function uPathPop(str:String):String
	{
		#if unifill
		var path = Unifill.uSplit(str, '/');
		path.pop();
		return path.join('/');
		#else
		var path = str.split('/');
		path.pop();
		return path.join('/');
		#end
	}

	public static function uTrimFinalCharIf(str:String, match:String):String
	{
		var uLength = Util.uLength(str);
		var last = Util.uLastIndexOf(str, match);
		if (last == uLength - 1)
		{
			str = Util.uSubstr(str, 0, uLength - 1);
			uLength = Util.uLength(str);
		}
		return str;
	}

	public static function uTrimFinalEndlines(str:String):String
	{
		var done = false;
		var fix = '';
		var last = '';
		while (!done)
		{
			var fix = Util.uTrimFinalCharIf(str, "\n");
			fix = Util.uTrimFinalCharIf(fix, "\r");
			if (fix == str)
			{
				done = true;
			}
			else
			{
				str = fix;
			}
		}
		return str;
	}

	public static function uTrimFirstCharIf(str:String, match:String):String
	{
		var uLength = Util.uLength(str);
		var first = Util.uIndexOf(str, match);
		if (first == 0)
		{
			str = Util.uSubstr(str, 1, uLength);
			uLength = Util.uLength(str);
		}
		return str;
	}

	public static function uTrimFirstEndlines(str:String):String
	{
		var done = false;
		var fix = '';
		var last = '';
		while (!done)
		{
			var fix = Util.uTrimFirstCharIf(str, "\n");
			fix = Util.uTrimFirstCharIf(fix, "\r");
			if (fix == str)
			{
				done = true;
			}
			else
			{
				str = fix;
			}
		}
		return str;
	}

	public static inline function uSplit(str:String, substr:String):Array<String>
	{
		#if unifill
		return Unifill.uSplit(str, substr);
		#else
		return str.split(substr);
		#end
	}

	public static function uSplitReplace(s:String, substr:String, by:String):String
	{
		if (uIndexOf(s, substr) == -1)
			return s;

		var arr = uSplit(s, substr);

		if (arr == null || arr.length < 2)
			return s;

		var sb:StringBuf = new StringBuf();
		for (i in 0...arr.length)
		{
			var bit = arr[i];
			sb.add(bit);
			if (i != arr.length - 1)
			{
				sb.add(by);
			}
		}

		return sb.toString();
	}

	public static inline function uSubstr(str:String, pos:Int, ?len:Int):String
	{
		#if unifill
		return Unifill.uSubstr(str, pos, len);
		#else
		return str.substr(pos, len);
		#end
	}

	public static inline function uSubstring(str:String, startIndex:Int, ?endIndex:Int):String
	{
		#if unifill
		return Unifill.uSubstring(str, startIndex, endIndex);
		#else
		return str.substring(startIndex, endIndex);
		#end
	}

	@:generic
	public static function filterUnique<T>(input:Array<T>)
	{
		var output = [];
		for (item in input)
		{
			if (output.indexOf(item) == -1)
			{
				// Item not yet in output array
				output.push(item);
			}
		}
		return output;
	}

	public static function indexOfInsens(arr:Array<String>, x:String, ?fromIndex:Int, ignoreConfig:Bool = false):Int
    {
        if (!PolymodConfig.caseInsensitiveZipLoading && !ignoreConfig) return arr.indexOf(x, fromIndex);
        x = x.toLowerCase();
        for (i => s in arr)
        {
            if (s.toLowerCase() == x) return i;
        }
        return -1;
    }

    public static inline function containsInsens(arr:Array<String>, x:String, ignoreConfig:Bool = false):Bool
    {
        return indexOfInsens(arr, x, ignoreConfig) != -1;
    }
}
