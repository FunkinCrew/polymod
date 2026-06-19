package polymod.format;

import json.JSONData;
import json.patch.JSONPatch;
import polymod.Polymod;
import polymod.util.Util;

class ParseRules
{
  private var formats:Map<String, BaseParseFormat>;

  public function new()
  {
    formats = new Map<String, BaseParseFormat>();
  }

  public function addType(extension:String, type:TextFileFormat)
  {
    var format:BaseParseFormat = switch (type)
    {
      case CSV: new CSVParseFormat(',', true);
      case TSV: new TSVParseFormat();
      case XML: new XMLParseFormat();
      case JSON: new JSONParseFormat();
      case LINES: new LinesParseFormat(EndLineType.LF);
      case PLAINTEXT: new PlainTextParseFormat();
      case SCRIPT: new ScriptParseFormat();
      default: new PlainTextParseFormat();
    }
    formats.set(extension, format);
  }

  public function get(extension:String):BaseParseFormat
  {
    return formats.get(extension);
  }

  public function addFormat(extension:String, format:BaseParseFormat)
  {
    formats.set(extension, format);
  }

  public function addFile(path:String, format:BaseParseFormat)
  {
    formats.set(path, format);
  }

  public static function getDefault():ParseRules
  {
    var rules = new ParseRules();
    rules.addFormat('csv', new CSVParseFormat(',', true));
    rules.addFormat('tsv', new TSVParseFormat());
    rules.addFormat('xml', new XMLParseFormat());
    rules.addFormat('json', new JSONParseFormat());
    rules.addFormat('txt', new PlainTextParseFormat());

    rules.addFormat("hxc", new ScriptParseFormat());
    for (ext in PolymodConfig.scriptClassExt)
    {
      rules.addFormat(ext, new ScriptParseFormat());
    }

    return rules;
  }
}

class CSVParseFormat implements BaseParseFormat
{
  public var format(default, null):TextFileFormat;
  public var isSimpleMode(get, null):Bool;
  public var delimiter:String;
  public var quotedCells:Bool;
  public var lookForHeaders:Bool;

  public function new(delimiter:String, quotedCells:Bool)
  {
    format = TextFileFormat.CSV;
    this.delimiter = delimiter;
    this.quotedCells = quotedCells;
  }

  private function get_isSimpleMode():Bool
  {
    return (delimiter == ',' && quotedCells == false);
  }

  public function parse(str:String):CSV
  {
    return polymod.format.CSV.parse(str, delimiter, quotedCells);
  }

  public function append(baseText:String, appendText:String, id:String):String
  {
    var endLine:String = "\n";
    if (baseText.indexOf('\r\n') != -1)
    {
      endLine = '\r\n';
    }
    if (lookForHeaders)
    {
      var baseCSV:polymod.format.CSV;
      var appendCSV:polymod.format.CSV;

      // Strip of a trailing endline from append if there is one
      var appendEndLine = '\n';
      if (appendText.indexOf('\r\n') != -1)
      {
        appendEndLine = '\r\n';
      }
      var appendLength = Util.uLength(appendText);
      var appendLast = Util.uLastIndexOf(appendText, appendEndLine);
      if (appendLast == appendLength - 1 || appendLast == appendLength - 2)
      {
        appendText = Util.uSubstr(appendText, 0, appendLength - Util.uLength(appendEndLine));
      }

      try
      {
        baseCSV = polymod.format.CSV.parseWithFormat(baseText, this);
        appendCSV = polymod.format.CSV.parseWithFormat(appendText, this);
      }
      catch (msg:Dynamic)
      {
        Polymod.error(ASSET_MERGE_FAILED, 'CSV append error ($id): $msg');
        return baseText;
      }

      var finalText:String = baseText;
      var finalLength = Util.uLength(finalText);

      var lastEndLine = Util.uLastIndexOf(finalText, endLine);
      var addFinalEndline = false;

      if (lastEndLine == finalLength - 1 || lastEndLine == finalLength - 2)
      {
        finalText = Util.uSubstr(finalText, 0, finalLength - Util.uLength(endLine));
        addFinalEndline = true;
      }

      var compareFields = 0;
      for (i in 0...baseCSV.fields.length)
      {
        var baseField = baseCSV.fields[i];
        var appendFieldExists = appendCSV.fields.indexOf(baseField) != -1;
        if (appendFieldExists) compareFields++;
      }

      if (lookForHeaders)
      {
        if (compareFields < Std.int(baseCSV.fields.length / 2))
        {
          Polymod.error(ASSET_APPEND_FAILED, 'Mod file ($id) is missing most or all of the expected header fields');
        }
      }

      var missingFields = [];

      for (r in 0...appendCSV.grid.length)
      {
        var line = '';
        for (bi in 0...baseCSV.fields.length)
        {
          var baseField = baseCSV.fields[bi];
          var appendField = appendCSV.fields.indexOf(baseField);
          if (appendField != -1)
          {
            var appendValue = appendCSV.grid[r][appendField];
            if (appendValue == null)
            {
              appendValue = '';
            }
            line += appendValue;
          }
          else
          {
            if (missingFields.indexOf(baseField) == -1)
            {
              missingFields.push(baseField);
            }
          }
          if (bi != baseCSV.fields.length - 1)
          {
            line += delimiter;
          }
        }
        finalText += endLine + line;
      }

      if (addFinalEndline)
      {
        finalText += endLine;
      }

      for (baseField in missingFields)
      {
        Polymod.warning(ASSET_APPEND_FAILED, 'Mod file ($id) is missing expected field "$baseField", values will default to empty string.');
      }

      return finalText;
    }
    return Util.appendCSVOrTSV(baseText, appendText, id);
  }

  public function merge(baseText:String, mergeText:String, id:String):String
  {
    var baseCSV:polymod.format.CSV;
    var mergeCSV:polymod.format.CSV;
    try
    {
      baseCSV = polymod.format.CSV.parseWithFormat(baseText, this);
      mergeCSV = polymod.format.CSV.parseWithFormat(mergeText, this);
    }
    catch (msg:Dynamic)
    {
      Polymod.error(ASSET_MERGE_FAILED, 'CSV merge error ($id): $msg');
      return baseText;
    }

    for (row in mergeCSV.grid)
    {
      var flag = row.length > 0 ? row[0] : '';
      if (flag != '')
      {
        for (i in 0...baseCSV.grid.length)
        {
          var otherRow = baseCSV.grid[i];
          var otherFlag = otherRow[0];
          if (flag == otherFlag)
          {
            for (j in 0...row.length)
            {
              if (j < otherRow.length)
              {
                otherRow[j] = row[j];
              }
            }
          }
        }
      }
    }
    var result = print(baseCSV);
    return result;
  }

  public function print(csv:polymod.format.CSV):String
  {
    var buf = new StringBuf();

    var dq = 0x22;

    for (i in 0...csv.fields.length)
    {
      buf.add(csv.fields[i]);
      if (i != csv.fields.length - 1)
      {
        buf.add(delimiter);
      }
    }

    var strSoFar = buf.toString();

    if (strSoFar.indexOf('\n') == -1)
    {
      buf.add(Std.string('\r\n'));
    }

    var grid = csv.grid;

    for (iy in 0...grid.length)
    {
      var row = grid[iy];
      for (ix in 0...row.length)
      {
        var cell = row[ix];
        if (quotedCells)
        {
          buf.addChar(dq);
        }
        buf.add(cell);
        if (quotedCells)
        {
          buf.addChar(dq);
        }
        if (ix != row.length - 1)
        {
          buf.add(delimiter);
        }
      }
      if (iy != grid.length - 1)
      {
        buf.add(Std.string('\r\n'));
      }
    }

    return buf.toString();
  }
}

class TSVParseFormat implements BaseParseFormat
{
  public var format(default, null):TextFileFormat;

  public function new()
  {
    format = TSV;
  }

  public function parse(str:String)
  {
    return polymod.format.TSV.parse(str);
  }

  public function append(baseText:String, appendText:String, id:String):String
  {
    return Util.appendCSVOrTSV(baseText, appendText, id);
  }

  public function merge(baseText:String, mergeText:String, id:String):String
  {
    var baseTSV = polymod.format.TSV.parse(baseText);
    var mergeTSV = polymod.format.TSV.parse(mergeText);
    for (row in mergeTSV.grid)
    {
      var flag = row.length > 0 ? row[0] : '';
      if (flag != '')
      {
        for (i in 0...baseTSV.grid.length)
        {
          var otherRow = baseTSV.grid[i];
          var otherFlag = otherRow[0];
          if (flag == otherFlag)
          {
            for (j in 0...row.length)
            {
              if (j < otherRow.length)
              {
                otherRow[j] = row[j];
              }
            }
          }
        }
      }
    }
    var result = print(baseTSV);
    return result;
  }

  public function print(tsv:TSV):String
  {
    var buf = new StringBuf();

    var tab = 0x09;

    for (i in 0...tsv.fields.length)
    {
      buf.add(tsv.fields[i]);
      if (i != tsv.fields.length - 1)
      {
        buf.addChar(tab);
      }
    }

    var strSoFar = buf.toString();

    if (strSoFar.indexOf('\n') == -1)
    {
      buf.add(Std.string('\r\n'));
    }

    var grid = tsv.grid;

    for (iy in 0...grid.length)
    {
      var row = grid[iy];
      for (ix in 0...row.length)
      {
        var cell = row[ix];
        buf.add(cell);
        if (ix != row.length - 1)
        {
          buf.addChar(tab);
        }
      }
      if (iy != grid.length - 1)
      {
        buf.add(Std.string('\r\n'));
      }
    }

    return buf.toString();
  }
}

class LinesParseFormat implements BaseParseFormat // <Array<String>>
{
  public var format(default, null):TextFileFormat;
  public var endline:EndLineType;

  public function new(endline:EndLineType)
  {
    format = LINES;
    this.endline = endline;
  }

  public function parse(str:String):Array<String>
  {
    if (str == null || str == '') return [];
    var other = '';
    var endl = '';
    switch (endline)
    {
      case LF:
        endl = '\n';
      case CR:
        endl = '\r';
      case CRLF:
        endl = '\r\n';
      default:
        endl = '\r';
        other = '\n';
    }
    if (other == '')
    {
      return str.split(endl);
    }
    else
    {
      str = StringTools.replace(str, other, endl);
      return str.split(endl);
    }
    return [];
  }

  public function append(baseText:String, appendText:String, id:String):String
  {
    return Util.uCombine([baseText, getEndl(), appendText]);
  }

  public function merge(baseText:String, mergeText:String, id:String):String
  {
    if (baseText == null || mergeText == '') return baseText;
    var lines = parse(baseText);
    if (lines == null || lines.length <= 0) return baseText;
    var mergeLines = parse(mergeText);
    if (mergeLines == null || mergeLines.length <= 1) return baseText;
    var pattern = mergeLines[0];
    var newLines = [];
    for (line in lines)
    {
      if (line.indexOf(pattern) == 0)
      {
        newLines = newLines.concat(mergeLines);
      }
      else
      {
        newLines.push(line);
      }
    }
    return Util.uJoin(newLines, getEndl());
  }

  public function print(lines:Array<String>):String
  {
    return lines.join(getEndl());
  }

  public function getEndl():String
  {
    return switch (endline)
    {
      case LF: '\n';
      case CR: '\r';
      case CRLF: '\r\n';
      default: '\n';
    }
  }
}

class XMLParseFormat implements BaseParseFormat // <Xml>
{
  public var format(default, null):TextFileFormat;
  public var prettyPrint:Bool = false;
  public var stripHeaders:Array<String>;
  public var stripFooters:Array<String>;

  public function new(prettyPrint:Bool = false, headers:Array<String> = null, footers:Array<String> = null)
  {
    if (headers == null) headers = [];
    if (footers == null) footers = [];
    stripHeaders = headers;
    stripFooters = footers;
    this.prettyPrint = prettyPrint;
    format = XML;
  }

  public function parse(str:String):Xml
  {
    return Xml.parse(str);
  }

  public function append(baseText:String, appendText:String, id:String):String
  {
    if (stripHeaders != null && stripFooters != null)
    {
      return Util.appendSpecialXML(baseText, appendText, stripHeaders, stripFooters);
    }
    else
    {
      return Util.appendXML(baseText, appendText);
    }
  }

  public function merge(baseText:String, mergeText:String, id:String):String
  {
    var basex:Xml = null;
    var mergex:Xml = null;

    try
    {
      basex = Xml.parse(baseText);
      mergex = Xml.parse(mergeText);
    }
    catch (msg:Dynamic)
    {
      throw 'Error parsing XML files during merge ($id): $msg';
    }

    try
    {
      XMLMerge.mergeXMLNodes(basex, mergex);
    }
    catch (msg:Dynamic)
    {
      throw 'Error combining XML files during merge ($id): $msg';
    }

    return print(basex);
  }

  public function print(xml:Xml):String
  {
    return haxe.xml.Printer.print(xml, prettyPrint);
  }
}

typedef TargetSignatureElement =
{
  var value:String;
  var arrayIndeces:Array<Int>;
}

typedef JsonMergeEntry =
{
  var target:String;
  var payload:Dynamic;
}

typedef JsonMergeStruct =
{
  var merge:Array<JsonMergeEntry>;
}

class JSONParseFormat implements BaseParseFormat
{
  public var format:TextFileFormat;

  /**
   * If replacer is given and is not null, it is used to retrieve the actual object to be encoded.
   * The replacer function takes two parameters, the key and the value being encoded.
   * Initial key value is an empty string.
   */
  public var replacer(default, null):Dynamic->Dynamic->Dynamic;

  /**
   * If space is given and is not null, the result will be pretty-printed. Successive levels will be indented by this string.
   */
  public var space(default, null):String;

  public function new(space:String = null, replacer:Dynamic->Dynamic->Dynamic = null)
  {
    this.replacer = replacer;
    this.space = space;
    format = JSON;
  }

  public function parse(str:String):JSONData
  {
    var result = JSONData.parse(~/(\r|\n|\t)/g.replace(str, ''));
    return result;
  }

  public function append(baseText:String, appendText:String, id:String):String
  {
    var baseJson:JSONData = parse(baseText);
    var appendJson:JSONData = parse(appendText);

    var patchData = convertJSONToPatches(appendJson);

    var finalJson = JSONPatch.applyPatches(baseJson, patchData);

    return print(finalJson);
  }

  /**
   * Convert a JSON object to an array of JSON patches, to append this JSON to another.
   */
  function convertJSONToPatches(json:Dynamic):Array<JSONData>
  {
    var keys = Reflect.fields(json);

    var patches:Array<JSONData> = [];

    for (key in keys)
    {
      var value = Reflect.field(json, key);
      patches.push({"op": "add", "path": '/${key}', "value": value});
    }

    return patches;
  }

  public function merge(baseText:String, mergeText:String, id:String):String
  {
    var baseJson:JSONData = parse(baseText);
    var mergeJson:JSONData = parse(mergeText);

    var finalJson = JSONPatch.applyPatches(baseJson, mergeJson);

    return print(finalJson);
  }

  public function print(data:Dynamic):String
  {
    return haxe.Json.stringify(data, replacer, space);
  }
}

class PlainTextParseFormat implements BaseParseFormat // <String>
{
  public var format(default, null):TextFileFormat;

  public function new()
  {
    format = PLAINTEXT;
  }

  public function parse(str:String):String
  {
    return str;
  }

  public function append(baseText:String, appendText:String, id:String):String
  {
    var lastChar = Util.uCharAt(baseText, Util.uLength(baseText) - 1);
    var joiner = '';

    var endLine = '\n';

    var crIndex = Util.uIndexOf(baseText, '\r');
    var lfIndex = Util.uIndexOf(baseText, '\n');

    if (crIndex != -1)
    {
      if (lfIndex == crIndex + 1)
      {
        endLine = '\r\n';
      }
    }

    if (lastChar != '\n')
    {
      joiner = endLine;
    }

    return Util.uCombine([baseText, joiner, appendText]);
  }

  public function merge(baseText:String, mergeText:String, id:String):String
  {
    Polymod.warning(ASSET_MERGE_FAILED, '($id) Plain text files do not support merge functionality!');
    return baseText;
  }

  public function print(str:String):String
  {
    return str;
  }
}

enum TextFileFormat
{
  PLAINTEXT;
  LINES;
  CSV;
  TSV;
  XML;
  JSON;
  SCRIPT;
}

enum EndLineType
{
  LF;
  CR;
  CRLF;
  ANY;
}
