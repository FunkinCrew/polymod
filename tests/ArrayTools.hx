package tests;

class ArrayTools
{
  public static function append<T>(array:Array<T>, values:Array<T>):Void
  {
    for (value in values)
    {
      array.push(value);
    }
  }
}
