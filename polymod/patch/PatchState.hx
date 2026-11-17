package polymod.patch;

/**
 * The state of a patchable function while it is running.
 */
@:allow(polymod.patch.Patches)
class PatchState
{
  /**
   * The object the function was called on, or null for a static function.
   */
  public var instance(default, null):Dynamic;

  /**
   * The arguments the original will be called with.
   */
  public var args:Array<Dynamic>;

  /**
   * The return value.
   */
  public var result:Dynamic = null;

  /**
   * Set to true from a prefix to stop the original from running.
   */
  public var skip(default, set):Bool = false;

  /**
   * Whether the original function ran.
   */
  public var ranOriginal(default, null):Bool = false;

  /**
   * The class that declares the patched function.
   */
  public var className(get, never):String;

  /**
   * The name of the patched function.
   */
  public var field(get, never):String;

  /**
   * The mod whose callback is running right now.
   */
  public var owner(default, null):Null<String> = null;

  var slot:PatchSlot;

  var skippedBy:Null<String> = null;

  function new(slot:PatchSlot, instance:Dynamic, args:Array<Dynamic>)
  {
    this.slot = slot;
    this.instance = instance;
    this.args = args;
  }

  function set_skip(value:Bool):Bool
  {
    if (value && skippedBy != null && skippedBy != owner) slot.reportSkipConflict(skippedBy, owner);
    if (value && skippedBy == null) skippedBy = owner;
    return skip = value;
  }

  function get_className():String
  {
    return slot.className;
  }

  function get_field():String
  {
    return slot.field;
  }
}
