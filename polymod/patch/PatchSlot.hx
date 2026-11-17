package polymod.patch;

import polymod.Polymod;

/**
 * Options for one patch callback.
 */
typedef PatchOptions =
{
  /**
   * Higher runs first. Defaults to 0.
   */
  var ?priority:Int;

  /**
   * Mod ids whose callbacks on this function must run after this one.
   */
  var ?before:Array<String>;

  /**
   * Mod ids whose callbacks on this function must run before this one.
   */
  var ?after:Array<String>;
}

/**
 * One prefix or postfix registered by a mod.
 */
class PatchEntry
{
  public var owner(default, null):String;
  public var fn(default, null):PatchState->Void;
  public var priority(default, null):Int;
  public var before(default, null):Array<String>;
  public var after(default, null):Array<String>;
  public var enabled:Bool = true;

  @:allow(polymod.patch.PatchSlot)
  var seq:Int;

  public function new(owner:String, fn:PatchState->Void, ?options:PatchOptions)
  {
    this.owner = owner;
    this.fn = fn;
    this.priority = options?.priority ?? 0;
    this.before = options?.before ?? [];
    this.after = options?.after ?? [];
  }
}

/**
 * A patchable function. Holds the list of patches and the original function.
 */
class PatchSlot
{
  public var className(default, null):String;
  public var field(default, null):String;

  public var prefixes(default, null):Array<PatchEntry> = [];
  public var postfixes(default, null):Array<PatchEntry> = [];

  @:allow(polymod.patch.Patches)
  var cls:Class<Dynamic>;

  @:allow(polymod.patch.Patches)
  var slotName:String;

  @:allow(polymod.patch.Patches)
  var origName:String;

  @:allow(polymod.patch.Patches)
  var isStatic:Bool;

  @:allow(polymod.patch.Patches)
  var staticOrig:Null<Dynamic> = null;

  var nextSeq:Int = 0;
  var reportedConflict:Bool = false;
  var reportedCycle:Bool = false;

  @:allow(polymod.patch.Patches)
  function new(cls:Class<Dynamic>, className:String, field:String, slotName:String, origName:String, isStatic:Bool)
  {
    this.cls = cls;
    this.className = className;
    this.field = field;
    this.slotName = slotName;
    this.origName = origName;
    this.isStatic = isStatic;
  }

  public function isEmpty():Bool
  {
    return prefixes.length == 0 && postfixes.length == 0;
  }

  @:allow(polymod.patch.Patches)
  function add(entry:PatchEntry, isPrefix:Bool):Void
  {
    entry.seq = nextSeq++;
    var list:Array<PatchEntry> = isPrefix ? prefixes : postfixes;
    list.push(entry);
    sortList(list);
  }

  @:allow(polymod.patch.Patches)
  function removeOwner(owner:String):Bool
  {
    var removed:Bool = false;
    for (list in [prefixes, postfixes])
    {
      var i:Int = list.length;
      while (i-- > 0)
      {
        if (list[i].owner != owner) continue;
        list.splice(i, 1);
        removed = true;
      }
    }
    return removed;
  }

  @:allow(polymod.patch.PatchState)
  function reportSkipConflict(first:String, second:String):Void
  {
    if (reportedConflict) return;
    reportedConflict = true;
    Polymod.warning(SCRIPT_PATCH, 'Mods "$first" and "$second" both skip $className.$field, only one of them can replace it. Use priority, before or after to choose which runs first.',
      SCRIPT_RUNTIME);
  }

  /**
   * Sorts a list of patches by priority, load order, and before/after constraints. Modifies the list in place.
   */
  function sortList(list:Array<PatchEntry>):Void
  {
    list.sort(function(a:PatchEntry, b:PatchEntry):Int {
      if (a.priority != b.priority) return b.priority - a.priority;
      var orderA:Int = Patches.loadOrderOf(a.owner);
      var orderB:Int = Patches.loadOrderOf(b.owner);
      if (orderA != orderB) return orderA - orderB;
      return a.seq - b.seq;
    });

    var hasConstraints:Bool = false;
    for (entry in list)
    {
      if (entry.before.length == 0 && entry.after.length == 0) continue;
      hasConstraints = true;
      break;
    }
    if (!hasConstraints) return;

    // mustPrecede[i] lists the entries that have to run before entry i.
    var mustPrecede:Array<Array<Int>> = [for (_ in list) []];
    for (i in 0...list.length)
    {
      for (j in 0...list.length)
      {
        if (i == j || list[i].owner == list[j].owner) continue;
        if (list[j].before.contains(list[i].owner) || list[i].after.contains(list[j].owner)) mustPrecede[i].push(j);
      }
    }

    var placed:Array<Bool> = [for (_ in list) false];
    var result:Array<PatchEntry> = [];
    while (result.length < list.length)
    {
      var picked:Int = -1;
      for (i in 0...list.length)
      {
        if (placed[i]) continue;
        var ready:Bool = true;
        for (j in mustPrecede[i])
        {
          if (placed[j]) continue;
          ready = false;
          break;
        }
        if (!ready) continue;
        picked = i;
        break;
      }

      if (picked == -1)
      {
        if (!reportedCycle)
        {
          reportedCycle = true;
          Polymod.warning(SCRIPT_PATCH, 'Patches on $className.$field have before/after rules that contradict each other, falling back to priority and load order.',
            SCRIPT_RUNTIME);
        }
        for (i in 0...list.length)
          if (!placed[i]) result.push(list[i]);
        break;
      }

      placed[picked] = true;
      result.push(list[picked]);
    }

    for (i in 0...result.length)
      list[i] = result[i];
  }
}
