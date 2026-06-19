package polymod.format;

/**
 * A simple TSV (tab separated values) structure
 * @author Lars Doucet
 */
class TSV extends CSV
{
  /**
   * Parses TSV formatted string into a usable data structure
   * End-line format will be auto-detected: a single "\r\n" will make it split lines based on Windows
   * style end-lines, otherwise it will attempt splitting based on unix-style "\n" end-lines.
   * @param	input tsv-formatted string
   */
  public static function parse(input:String):TSV
  {
    var endline:String = "\n";
    if (input.indexOf("\r\n") != -1) endline = "\r\n";
    var lines = input.split(endline);
    var fieldLine = lines.shift();
    var fields = fieldLine.split("\t");
    var grid = [];
    for (line in lines)
    {
      while (line.charAt(line.length - 1) == "\t") // trim trailing tabs
      {
        line = line.substr(0, line.length - 1);
      }
      var cells = line.split("\t");
      grid.push(cells);
    }
    var tsv = new TSV();
    tsv.fields = fields;
    tsv.grid = grid;
    return tsv;
  }

  function new()
  {
    super();
  }
}
