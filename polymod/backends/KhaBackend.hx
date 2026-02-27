package polymod.backends;

#if !kha
class KhaBackend extends StubBackend
{
  public function new()
  {
    super();
    Polymod.error(POLYMOD_FUNCTIONALITY_NOT_IMPLEMENTED, 'KhaBackend requires the kha library, did you forget to install it?', INIT);
  }
}
#else
class KhaBackend extends StubBackend
{
  public function new()
  {
    super();
    Polymod.error(POLYMOD_FUNCTIONALITY_NOT_IMPLEMENTED, 'Kha support in Polymod has not been implemented yet', INIT);
  }
}
#end
