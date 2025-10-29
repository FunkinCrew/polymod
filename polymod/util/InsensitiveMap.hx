package polymod.util;

import haxe.ds.StringMap;
import haxe.Constraints.IMap;

/**
 * A string map which treats any letter cases the same (case insensitive).
 * Unlike other maps, if a value already exists it won't be overwritten.
 */
class InsensitiveMap<T> implements IMap<String, T> {
    private var data:Map<String, T> = [];
    private var originalKeys:Map<String, String> = [];

    public function new() {}

    public inline function get(key:String):Null<T> {
      return data.get(key.toLowerCase());
    }

    public function set(key:String, value:T):Void {
      final lowerKey = key.toLowerCase();
      if (data.exists(lowerKey)) return;

      data.set(lowerKey, value);
      originalKeys.set(lowerKey, key);
    }

    public inline function exists(key:String):Bool {
      return data.exists(key.toLowerCase());
    }

    public function remove(key:String):Bool {
      final lowerKey = key.toLowerCase();
      originalKeys.remove(lowerKey);
      return data.remove(lowerKey);
    }

    public function clear():Void {
      data.clear();
      originalKeys.clear();
    }

    public function copy():InsensitiveMap<T> {
      final res = new InsensitiveMap();
      res.data = data.copy();
      res.originalKeys = originalKeys.copy();
      return res;
    }

    public inline function keys():Iterator<String> {
      return originalKeys.iterator();
    }

    public function keyValueIterator() {
      return {
        final it = originalKeys.keys();
        return {
            hasNext: it.hasNext,
            next: function() {
              final lowerKey = it.next();
              final originalKey = originalKeys.get(lowerKey);
              return { key: originalKey, value: data.get(lowerKey) };
            }
        };
      };
  }

    public inline function iterator() {
        return data.iterator();
    }

    public function toString():String {
        final parts = [];
        for (key in keys()) {
            parts.push('$key => ${get(key)}');
        }
        return '{' + parts.join(', ') + '}';
    }
}
