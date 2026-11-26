package tests;

class MapTools
{
  public static function append<K, V>(map:Map<K, V>, values:Map<K, V>):Void
  {
    for (key in values.keys())
    {
      map[key] = values[key];
    }
  }
}
