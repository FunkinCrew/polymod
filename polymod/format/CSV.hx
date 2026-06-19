package polymod.format;

import polymod.format.ParseRules.CSVParseFormat;

/**
 * A simple CSV (comma separated values) structure
 * @author Lars Doucet
 */
class CSV
{
  public var fields:Array<String>;
  public var grid:Array<Array<String>>;

  function new() {}

  /**
   * Parses CSV formatted string into a usable data structure
   * @param	input csv-formatted string
   * @param	delimeter string that separates cells
   * @param	quotedCells	whether all cells are quoted (true) or all cells are unquoted (false)
   * @return	the parsed CSV data
   */
  public static function parse(input:String, delimiter:String = ',', quotedCells:Bool = true):CSV
  {
    var csv = new CSV();
    @:privateAccess csv._parse(input, delimiter, quotedCells);
    return csv;
  }

  /**
   * Parses CSV formatted string into a usable data structure
   * @param	format details about the parse format
   * @return	the parsed CSV data
   */
  public static function parseWithFormat(input:String, format:CSVParseFormat):CSV
  {
    if (format.isSimpleMode)
    {
      return CSV.parseSimple(input);
    }
    else
    {
      return CSV.parse(input, format.delimiter, format.quotedCells);
    }
  }

  /**
   * Parses CSV assuming 1) All cells are unquoted and 2) No commas or end-lines exist within a cell
   * End-line format will be auto-detected: a single '\r\n' will make it split lines based on Windows
   * style end-lines, otherwise it will attempt splitting based on unix-style '\n' end-lines.
   * @param	input csv-formatted string
   * @return	the parsed CSV data
   */
  public static function parseSimple(input:String):CSV
  {
    var endline:String = '\n';
    if (input.indexOf('\r\n') != -1) endline = '\r\n';
    var lines = input.split(endline);
    var fieldLine = lines.shift();
    var fields = fieldLine.split(',');
    var grid = [];
    for (line in lines)
    {
      var cells = line.split(',');
      grid.push(cells);
    }
    var csv = new CSV();
    csv.fields = fields;
    csv.grid = grid;
    return csv;
  }

  public function destroy():Void
  {
    clearArray(grid);
    clearArray(fields);
    grid = null;
    fields = null;
  }

  private var _rgx:EReg = null;

  private var _delimiter:String = '';
  private var _quoted:Bool = false;

  private function _parse(input:String, delimiter:String = ',', quoted:Bool = true)
  {
    _delimiter = delimiter;
    _quoted = quoted;
    if (input != '')
    {
      processRows(getRows(input));
    }
  }

  private function clearArray(array:Array<Dynamic>):Void
  {
    if (array == null) return;
    var i:Int = array.length - 1;
    while (i >= 0)
    {
      destroyThing(array[i]);
      array[i] = null;
      array.splice(i, 1);
      i--;
    }
    array = null;
  }

  private function destroyThing(thing:Dynamic):Void
  {
    if (thing == null) return;

    if (Std.isOfType(thing, Array))
    {
      clearArray(thing);
    }

    thing = null;
  }

  private function getCells(row:String):Array<String>
  {
    if (_rgx == null)
    {
      // If the last cell in the row ends with the delimeter, trim it off before splitting
      if (row.charAt(row.length - 1) == _delimiter)
      {
        row = row.substr(0, row.length - 1);
      }

      if (_delimiter == ',')
      {
        _rgx = ~/,(?=(?:[^\x22]*\x22[^\x22]*\x22)*(?![^\x22]*\x22))/gm;
        // Matches a well-formed CSV cell, ie 'thing1' or 'thing , 5' etc
        // '\x22' is the invocation for the double-quote mark.
        // UTF-8 ONLY!!!!
      }
      else
      {
        // You can provide your own customer delimeter, but we generally don't recommend it
        _rgx = new EReg(_delimiter + '(?=(?:[^\x22]*\x22[^\x22]*\x22)*(?![^\x22]*\x22))', 'gm');
      }
    }
    return _rgx.split(row);
  }

  private function getRows(input:String):Array<String>
  {
    var endl:String = '\r\n';

    if (input.indexOf('\r\n') == -1) // no windows-style endlines...
    {
      endl = '\n'; // try unix-style instead...
    }

    return input.split(endl);
  }

  private function processCells(cells:Array<String>, row:Int = 0):Void
  {
    var row_array:Array<String> = null;

    if (grid == null)
    {
      grid = new Array<Array<String>>();
      fields = [];
    }

    row_array = [];

    for (i in 0...cells.length)
    {
      var cell:String = '';
      if (_quoted)
      {
        cell = cells[i].substr(1, cells[i].length - 2);
      }
      else
      {
        cell = cells[i];
      }

      if (row == 0)
      {
        fields.push(cell); // get the fields
      }
      else
      {
        row_array.push(cell); // get the row cells
      }
    }

    grid.push(row_array);
    clearArray(cells);
    cells = null;
  }

  private function processRows(rows:Array<String>):Void
  {
    for (i in 0...rows.length)
    {
      processCells(getCells(rows[i]), i);
    }
  }
}
