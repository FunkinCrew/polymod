package polymod.hscript._internal;

import haxe.ds.ObjectMap;

@:forward
@:access(polymod.hscript._internal.PolymodScriptClass)
abstract PolymodAbstractScriptClass(PolymodScriptClass) from PolymodScriptClass
{
  static final fieldsCache:ObjectMap<Dynamic, Array<String>> = new ObjectMap();

  private function resolveField(name:String):Dynamic
  {
    switch (name)
    {
      case "superClass":
        return this.superClass;
      case "createSuperClass":
        return this.createSuperClass;
      case "findFunction":
        return this.findFunction;
      case "callFunction":
        return this.callFunction;
      case _:
        if (this.findFunction(name) != null)
        {
          return Reflect.makeVarArgs(function(args:Array<Dynamic>) {
            return this.callFunction(name, args);
          });
        }
        else if (this.findVar(name) != null)
        {
          var v = this.findVar(name, true);

          @:privateAccess
          switch (v.get)
          {
            case "get":
              final getName = 'get_$name';
              if (!this._interp._propTrack.exists(getName))
              {
                this._interp._propTrack.set(getName, true);
                var r:Dynamic = null;
                // Children may override it
                if (this.topASC != null && this.topASC.findFunction(getName) != null)
                {
                  r = this.topASC.callFunction(getName);
                }
                else
                {
                  r = this.callFunction(getName);
                }
                this._interp._propTrack.remove(getName);
                return r;
              }
              else
              {
                // Fallback like it's a normal variable.
              }

            case "null":
              return this._interp.error(EInvalidPropGet(name));
          }

          var varValue:Dynamic = null;
          if (!this._interp.variables.exists(name))
          {
            if (v.expr != null)
            {
              varValue = this._interp.exprWithType(v.expr, v.type);
              this._interp.variables.set(name, varValue);
            }
          }
          else
          {
            varValue = this._interp.variables.get(name);
          }
          return varValue;
        }
        else if (this.superClass == null)
        {
          @:privateAccess this._interp.error(EInvalidAccess(name));
        }
        else if (Type.getClass(this.superClass) == null)
        {
          // Anonymous structure
          if (Reflect.hasField(this.superClass, name))
          {
            return Reflect.field(this.superClass, name);
          }
          else
          {
            @:privateAccess this._interp.error(EInvalidAccess(name));
          }
        }
        else if (Std.isOfType(this.superClass, PolymodScriptClass))
        {
          // PolymodScriptClass
          var superScriptClass:PolymodAbstractScriptClass = cast(this.superClass, PolymodScriptClass);
          try
          {
            return superScriptClass.fieldRead(name);
          }
          catch (e:Dynamic) {}
        }
        else
        {
          // Class object
          try
          {
            return getClassObjectField(this.superClass, name);
          }
          catch (e:String)
          {
            @:privateAccess this._interp.error(EInvalidAccess(name));
          }
        }
    }

    if (this.superClass == null)
    {
      throw "field '" + name + "' does not exist in script class '" + this.fullyQualifiedName + "'";
    }
    else
    {
      throw "field '" + name + "' does not exist in script class '" + this.fullyQualifiedName + "' or super class '"
        + Type.getClassName(Type.getClass(this.superClass)) + "'";
    }
  }

  @:op(a.b) public function fieldRead(name:String):Dynamic
  {
    return resolveField(name);
  }

  public function fieldExists(name:String):Bool
  {
    final KNOWN_FIELDS:Array<String> = ["superClass", "createSuperClass", "findFunction", "callFunction"];
    if (KNOWN_FIELDS.contains(name)) return true;

    // Check the script.

    if (this.findFunction(name) != null) return true;
    if (this.findVar(name) != null) return true;

    // Else, we have to query the superclass.

    if (this.superClass == null) return false;

    // Anonymous structure
    if (Type.getClass(this.superClass) == null)
    {
      return Reflect.hasField(this.superClass, name);
    }

    // Scripts extending scripts
    if (Std.isOfType(this.superClass, PolymodScriptClass))
    {
      var superScriptClass:PolymodAbstractScriptClass = cast(this.superClass, PolymodScriptClass);
      // Yay recursion!
      return superScriptClass.fieldExists(name);
    }

    // Script extends a class object, use standard reflection
    if (hasClassObjectField(this.superClass, name)) return true;

    return false;
  }

  @:op(a.b) public function fieldWrite(name:String, value:Dynamic):Dynamic
  {
    if (this.findVar(name) != null)
    {
      var decl = this.findVar(name, true);
      if (decl.isfinal && decl.expr != null) // The variable already exists and has a set value.
      {
        @:privateAccess this._interp.error(EInvalidFinalSet(name));
      }

      @:privateAccess
      switch (decl.set)
      {
        case "set":
          final setName = 'set_$name';
          if (!this._interp._propTrack.exists(setName))
          {
            this._interp._propTrack.set(setName, true);
            var r:Dynamic = null;
            // Children may override it
            if (this.topASC != null && this.topASC.findFunction(setName) != null)
            {
              r = this.topASC.callFunction(setName, [value]);
            }
            else
            {
              r = this.callFunction(setName, [value]);
            }
            this._interp._propTrack.remove(setName);
            return r;
          }

        case "never" | "null":
          return this._interp.error(EInvalidPropSet(name));
      }

      this._interp.variables.set(name, value);
      return value;
    }
    else if (this.superClass != null && Std.isOfType(this.superClass, PolymodScriptClass))
    {
      var superScriptClass:PolymodAbstractScriptClass = cast(this.superClass, PolymodScriptClass);
      try
      {
        return superScriptClass.fieldWrite(name, value);
      }
      catch (e:Dynamic) {}
    }
    else
    {
      // Class object
      if (setClassObjectField(this.superClass, name, value))
      {
        return value;
      }

      @:privateAccess this._interp.error(EInvalidAccess(name));
    }

    if (this.superClass == null)
    {
      @:privateAccess this._interp.error(EInvalidAccess(name));
    }
    else
    {
      @:privateAccess this._interp.error(EInvalidAccess(name));
    }
    return null;
  }

  static function retrieveClassObjectFields(o:Dynamic):Array<String>
  {
    final superClassCls = Type.getClass(o);
    if (superClassCls == null) throw "Provided object isn't a class";

    var fields = fieldsCache.get(superClassCls);
    if (fields == null)
    {
      fields = Type.getInstanceFields(superClassCls);
      fieldsCache.set(superClassCls, fields);
    }

    return fields;
  }

  private static function getClassObjectField(o:Dynamic, field:String):Null<Dynamic>
  {
    var fields = retrieveClassObjectFields(o);
    if (fields.contains(field) || fields.contains('get_$field')) return Reflect.getProperty(o, field);

    throw 'No such field $field';
  }

  private static function setClassObjectField(o:Dynamic, field:String, value:Dynamic):Bool
  {
    var fields = retrieveClassObjectFields(o);
    if (fields.contains(field) || fields.contains('set_$field'))
    {
      Reflect.setProperty(o, field, value);
      return true;
    }
    return false;
  }

  private static function hasClassObjectField(o:Dynamic, field:String):Bool
  {
    var fields = retrieveClassObjectFields(o);
    if (fields.contains(field) || fields.contains('get_$field') || fields.contains('set_$field')) return true;

    return false;
  }
}
