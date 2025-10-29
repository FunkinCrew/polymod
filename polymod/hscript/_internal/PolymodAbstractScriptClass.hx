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
					var fn = this.findFunction(name);
					var nargs = 0;
					if (fn.args != null)
					{
						nargs = fn.args.length;
					}
					switch (nargs)
					{
						case 0: return this.callFunction0.bind(name);
						case 1: return this.callFunction1.bind(name, _);
						case 2: return this.callFunction2.bind(name, _, _);
						case 3: return this.callFunction3.bind(name, _, _, _);
						case 4: return this.callFunction4.bind(name, _, _, _, _);
						#if neko
						case _: @:privateAccess this._interp.error(ECustom("only 4 params allowed in script class functions (.bind limitation)"));
						#else
						case 5: return this.callFunction5.bind(name, _, _, _, _, _);
						case 6: return this.callFunction6.bind(name, _, _, _, _, _, _);
						case 7: return this.callFunction7.bind(name, _, _, _, _, _, _, _);
						case 8: return this.callFunction8.bind(name, _, _, _, _, _, _, _, _);
						case _: @:privateAccess this._interp.error(ECustom("only 8 params allowed in script class functions (.bind limitation)"));
						#end
					}
				}
				else if (this.findVar(name) != null)
				{
					var v = this.findVar(name);

					@:privateAccess
					switch (v.get) {
						case "get":
							final getName = 'get_$name';
							if (!this._interp._propTrack.exists(getName)) {
								this._interp._propTrack.set(getName, true);
								var r = this.callFunction(getName);
								this._interp._propTrack.remove(getName);
								return r;
							}
							// Fallback like it's a normal variable.
							// If it doesn't have a "physical field" and @:isVar isn't set
							// an error will be thrown so doing this is fine.

						case "null":
							return this._interp.errorEx(EInvalidPropGet(name));
					}

					var varValue:Dynamic = null;
					if (this._interp.variables.exists(name) == false)
					{
						if (v.expr != null)
						{
							varValue = this._interp.expr(v.expr);
							this._interp.variables.set(name, varValue);
						}
					}
					else
					{
						varValue = this._interp.variables.get(name);
					}
					return varValue;
				}
				else if (this.superClass == null) {
					// @:privateAccess this._interp.error(EInvalidAccess(name));
					throw 'field "$name" does not exist in script class ${this.fullyQualifiedName}"';
				} else if (Type.getClass(this.superClass) == null) {
					// Anonymous structure
					if (Reflect.hasField(this.superClass, name)) {
						return Reflect.field(this.superClass, name);
					} else {
						// @:privateAccess this._interp.error(EInvalidAccess(name));
						throw 'field "$name" does not exist in script class ${this.fullyQualifiedName}" or super class "${Type.getClassName(Type.getClass(this.superClass))}"';
					}
				} else if (Std.isOfType(this.superClass, PolymodScriptClass)) {
					// PolymodScriptClass
					var superScriptClass:PolymodAbstractScriptClass = cast(this.superClass, PolymodScriptClass);
					try
					{
						return superScriptClass.fieldRead(name);
					}
					catch (e:Dynamic)
					{
					}
				} else {
					// Class object
					try {
						return getClassObjectField(this.superClass, name);
					}
					catch (e:String)
					{
						@:privateAccess this._interp.error(EInvalidAccess(name));
						//throw "field '" + name + "' does not exist in script class '" + this.fullyQualifiedName + "' or super class '" + Type.getClassName(Type.getClass(this.superClass)) + "'";
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

	@:op(a.b) public function fieldWrite(name:String, value:Dynamic):Dynamic
	{
		switch (name)
		{
			case _:
				if (this.findVar(name) != null)
				{
					if (this.findVar(name).isfinal && this.findVar(name).expr != null) // The variable already exists and has a set value.
					{
						throw "Invalid access to field " + name;
						return null;
					}

					var decl = this.findVar(name);
					@:privateAccess
					switch (decl.set) {
						case "set":
							final setName = 'set_$name';
							if (!this._interp._propTrack.exists(setName)) {
								this._interp._propTrack.set(setName, true);
								var r = this.callFunction(setName, [value]);
								this._interp._propTrack.remove(setName);
								return r;
							}

						case "never" | "null":
							return this._interp.errorEx(EInvalidPropSet(name));
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
					catch (e:Dynamic)
					{
					}
				}
				else {
					// Class object
					if (setClassObjectField(this.superClass, name, value)) {
						return value;
					}

					@:privateAccess this._interp.error(EInvalidAccess(name));
					// throw "field '" + name + "' does not exist in script class '" + this.fullyQualifiedName + "' or super class '" + Type.getClassName(Type.getClass(this.superClass)) + "'";
				}
		}

		if (this.superClass == null)
		{
			@:privateAccess this._interp.error(EInvalidAccess(name));
			// throw "field '" + name + "' does not exist in script class '" + this.fullyQualifiedName + "'";
		}
		else
		{
			@:privateAccess this._interp.error(EInvalidAccess(name));
			// throw "field '" + name + "' does not exist in script class '" + this.fullyQualifiedName + "' or super class '" + Type.getClassName(Type.getClass(this.superClass)) + "'";
		}
	}

	private static function retrieveClassObjectFields(o:Dynamic):Array<String>
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
		if (fields.contains(field) || fields.contains('get_$field'))
			return Reflect.getProperty(o, field);

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
}
