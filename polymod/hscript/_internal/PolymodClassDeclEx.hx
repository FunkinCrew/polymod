package polymod.hscript._internal;

import hscript.Expr.ClassDecl;
import hscript.Expr.FieldDecl;
import polymod.hscript._internal.PolymodScriptClass;

/**
 * A scripted class declaration, with a package declaration, imports, and potentially static fields.
 */
typedef PolymodClassDeclEx =
{
	> ClassDecl,
	/**
	 * Save performance and improve sandboxing by resolving imports at interpretation time.
	 */
	@:optional var imports:Map<String, PolymodClassImport>;
	@:optional var importsToValidate:Map<String, PolymodClassImport>;
	@:optional var pkg:Array<String>;

	@:optional var staticFields:Array<FieldDecl>;
	@:optional var usings:Map<String, PolymodClassImport>;
}

/**
 * An imported class or enumeration.
 */
typedef PolymodClassImport = {
	@:optional var name:String;
	@:optional var pkg:Array<String>;
	@:optional var fullPath:String; // pkg.pkg.pkg.name
	@:optional var cls:Class<Dynamic>;
	@:optional var enm:Enum<Dynamic>;
}

class PolymodStaticClassReference {
	public var cls:PolymodClassDeclEx;

	public function new(cls:PolymodClassDeclEx) {
		this.cls = cls;
	}

	public static function tryBuild(clsName:String):Null<PolymodStaticClassReference> {
		@:privateAccess {
			if (PolymodInterpEx._scriptClassDescriptors.exists(clsName)) {
				return new PolymodStaticClassReference(PolymodInterpEx._scriptClassDescriptors.get(clsName));
			} else {
				return null;
			}
		}
	}

	/**
	 * Return a scripted instance of this script class.
	 * @param args
	 * @return Dynamic
	 */
	public function instantiate(?args:Array<Dynamic>):Dynamic {
		var asc:PolymodAbstractScriptClass = buildASC(args);

		if (asc == null)
		{
			polymod.Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Could not construct instance of scripted class (${getFullyQualifiedName()})');
			return null;
		}

		var scriptedObj = asc.superClass;
		Reflect.setField(scriptedObj, '_asc', asc);
		return scriptedObj;
	}

	public function buildASC(?args:Array<Dynamic>):PolymodAbstractScriptClass {
		return new PolymodScriptClass(cls, args);
	}

	public function callFunction(funcName:String, ?args:Array<Dynamic>):Dynamic {
		return PolymodScriptClass.callScriptClassStaticFunction(getFullyQualifiedName(), funcName, args);
	}

	public function getField(fieldName:String):Dynamic {
		return PolymodScriptClass.getScriptClassStaticField(getFullyQualifiedName(), fieldName);
	}

	public function setField(fieldName:String, fieldValue:Dynamic):Dynamic {
		return PolymodScriptClass.setScriptClassStaticField(getFullyQualifiedName(), fieldName, fieldValue);
	}

	public function getFullyQualifiedName():String {
		if (this.cls.pkg != null && this.cls.pkg.length > 0) {
			return this.cls.pkg.join(".") + "." + this.cls.name;
		}
		return this.cls.name;
	}

	public function toString():String {
		return 'PolymodStaticClassReference(${getFullyQualifiedName()})';
	}
}
