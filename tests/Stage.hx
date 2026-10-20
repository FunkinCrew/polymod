package tests;

class Stage
{
  public var stageId:String;
  public var name:String = "base";
  public var count:Int = 0;

<<<<<<< Updated upstream
  public function new(stageId:String)
  {
    this.stageId = stageId;
=======
  public function new(id:String)
  {
    stageId = id;
>>>>>>> Stashed changes
  }

  public function update(amount:Int):Int
  {
    count += amount;
    return count;
  }
}
