package tests;

class Stage
{
  public var stageId:String;
  public var name:String = "base";
  public var count:Int = 0;

  public function new(id:String)
  {
    stageId = id;
  }

  public function update(amount:Int):Int
  {
    count += amount;
    return count;
  }
}
