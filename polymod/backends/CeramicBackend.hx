package polymod.backends;

#if !ceramic
class CeramicBackend extends StubBackend
{
  public function new()
  {
    super();
    Polymod.error(FUNCTIONALITY_NOT_IMPLEMENTED, 'CeramicBackend requires the ceramic library, did you forget to install it?');
  }
}
#else
class CeramicBackend extends StubBackend
{
  public function new()
  {
    super();
    Polymod.error(FUNCTIONALITY_NOT_IMPLEMENTED, 'CeramicBackend support in Polymod has not been implemented yet');
  }
}
#end
