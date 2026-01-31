package polymod.backends;

class CastleBackend extends StubBackend
{
  public function new()
  {
    super();
    Polymod.error(FUNCTIONALITY_NOT_IMPLEMENTED, 'CastleDB support in Polymod has not been implemented yet');
  }
}
