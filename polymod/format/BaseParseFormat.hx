package polymod.format;

import polymod.format.ParseRules;

interface BaseParseFormat
{
  public var format(default, null):TextFileFormat;
  public function append(baseText:String, mergeText:String, id:String):String; // { return baseText; }
  public function merge(baseText:String, mergeText:String, id:String):String; // { return baseText; }
}
