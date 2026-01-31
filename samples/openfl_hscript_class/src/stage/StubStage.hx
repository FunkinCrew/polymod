package stage;

class StubStage extends Stage
{
  public function new()
  {
    super('stub');
    this.stageName = "Stub Stage";
  }

  public override function create()
  {
    super.create();
  }
}
