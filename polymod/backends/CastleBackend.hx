package polymod.backends;

class CastleBackend extends StubBackend
{
  public function new()
  {
    super();
    Polymod.error(POLYMOD_FUNCTIONALITY_NOT_IMPLEMENTED, 'CastleDB support in Polymod has not been implemented yet', INIT);
  }
}
