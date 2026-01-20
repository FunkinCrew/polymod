package polymod.hscript._internal;

#if hscript
import haxe.ds.ObjectMap;
import hscript.Expr.FieldDecl;
import hscript.Expr.FunctionDecl;
import hscript.Expr.VarDecl;
import hscript.Printer;
import polymod.hscript._internal.PolymodClassDeclEx;

using StringTools;

/**
 * Provides handlers for scripted classes
 * Based on code by Ian Harrigan
 * @see https://github.com/ianharrigan/hscript-ex
 */
@:access(hscript.Interp)
@:allow(polymod.Polymod)
class PolymodScriptClass
{
	/*
	 * STATIC VARIABLES
	 */
	private static final scriptInterp = new PolymodInterpEx(null, null);

	/**
	 * Provide a class name along with a corresponding class to override imports.
	 * You can set the value to `null` to prevent the class from being imported.
	 */
	public static final importOverrides:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

	/**
	 * Provide a class name along with a corresponding class to import it in every scripted class.
	 */
	public static final defaultImports:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

	/**
	 * Provide a class with an array of its static fields to blacklist them.
	 * Blacklisted fields cannot be gotten or set.
	 */
	public static final blacklistedStaticFields:ObjectMap<Dynamic, Array<String>> = new ObjectMap<Dynamic, Array<String>>();

	/**
	 * Provide a class name with an array of its instance fields to blacklist them.
	 * Needs to be a string map because class instances won't point to the same reference.
	 * Blacklisted fields cannot be gotten or set.
	 */
	public static final blacklistedInstanceFields:Map<String, Array<String>> = new Map<String, Array<String>>();

	/*
	 * STATIC METHODS
	 */
	/**
	 * Register a scripted class by parsing the text of that script.
	 */
	static function registerScriptClassByString(body:String, path:String = null):Void
	{
		scriptInterp.addModule(body, path == null ? 'hscriptClass' : 'hscriptClass($path)');
	}

	/**
	 * STATIC PROPERTIES
	 */

	/**
	 * Define a list of script classes to override the default behavior of Polymod.
	 * For example, script classes should import `ScriptedSprite` instead of `Sprite`.
	 */
	public static var scriptClassOverrides(get, never):Map<String, Class<Dynamic>>;
	static var _scriptClassOverrides:Map<String, Class<Dynamic>> = null;

	static function get_scriptClassOverrides():Map<String, Class<Dynamic>> {
		if (_scriptClassOverrides == null) {
			_scriptClassOverrides = new Map<String, Class<Dynamic>>();

			var baseScriptClassOverrides:Map<String, Class<Dynamic>> = PolymodScriptClassMacro.listHScriptedClasses();

			for (key => value in baseScriptClassOverrides) {
				_scriptClassOverrides.set(key, value);
			}
		}

		return _scriptClassOverrides;
	}

	/**
	 * Define a list of all the abstracts we have available at compile time,
	 * and map them to internal implementation classes.
	 * We use this to access the functions of these abstracts.
	 */
	public static var abstractClassImpls(get, never):Map<String, Class<Dynamic>>;
	static var _abstractClassImpls:Map<String, Class<Dynamic>> = null;

	static function get_abstractClassImpls():Map<String, Class<Dynamic>> {
		if (_abstractClassImpls == null) {
			_abstractClassImpls = new Map<String, Class<Dynamic>>();

			var baseAbstractClassImpls:Map<String, Class<Dynamic>> = PolymodScriptClassMacro.listAbstractImpls();

			for (key => value in baseAbstractClassImpls) {
				_abstractClassImpls.set(key, value);
			}
		}

		return _abstractClassImpls;
	}

	public static var abstractClassStatics(get, never):Map<String, Class<Dynamic>>;
	static var _abstractClassStatics:Map<String, Class<Dynamic>> = null;

	static function get_abstractClassStatics():Map<String, Class<Dynamic>> {
		if (_abstractClassStatics == null) {
			_abstractClassStatics = new Map<String, Class<Dynamic>>();

			var baseAbstractClassStatics:Map<String, Class<Dynamic>> = PolymodScriptClassMacro.listAbstractStatics();

			for (key => value in baseAbstractClassStatics) {
				_abstractClassStatics.set(key, value);
			}
		}

		return _abstractClassStatics;
	}

	/**
	 * Register a scripted class by retrieving the script from the given path.
	 */
	static function registerScriptClassByPath(path:String):Void
	{
		@:privateAccess {
			var scriptBody = Polymod.assetLibrary.getText(path);
			if (scriptBody == null) {
				Polymod.error(SCRIPT_PARSE_ERROR, 'Error while loading script "${path}", could not retrieve script contents!');
				return;
			}
			try
			{
				registerScriptClassByString(scriptBody, path);
			}
			catch (err:PolymodExprEx.ErrorEx)
			{
				var errLine:String = #if hscriptPos '${err.line}' #else "#???" #end;
				#if hscriptPos
				switch (err.e)
				#else
				switch (err)
				#end
				{
					case EUnexpected(s):
						Polymod.error(SCRIPT_PARSE_ERROR,
							'Error while parsing function ${path}#${errLine}: EUnexpected' + '\n' +
							'Unexpected token "${s}", is there invalid syntax on this line?');
					case EClassUnresolvedSuperclass(cls, reason):
						Polymod.error(SCRIPT_PARSE_ERROR,
							'Error while parsing class ${path}#${errLine}: EClassUnresolvedSuperclass' + '\n' +
							'Unresolved superclass "${cls}", ${reason}');
					default:
						Polymod.error(SCRIPT_PARSE_ERROR, 'Error while executing script ${path}#${errLine}: ' + '\n' + 'An unknown error occurred: ${err}');
				}
			} catch (err:hscript.Expr.Error) {
				var errLine:String = #if hscriptPos '${err.line}' #else "#???" #end;
				#if hscriptPos
				switch (err.e)
				#else
				switch (err)
				#end
				{
					case EUnexpected(s):
						Polymod.error(SCRIPT_PARSE_ERROR,
							'Error while parsing script ${path}#${errLine}: EUnexpected' + '\n' +
							'Unexpected error: Unexpected token "${s}", is there invalid syntax on this line?');
					default:
						Polymod.error(SCRIPT_PARSE_ERROR, 'Error while executing script ${path}#${errLine}: ' + '\n' + 'An unknown error occurred: ${err}');
				}
			}
		}
	}

	static function registerScriptClassByPathAsync(path:String):lime.app.Future<Bool>
	{
		var promise = new lime.app.Promise<Bool>();

		if (!Polymod.assetLibrary.exists(path)) {
			Polymod.error(SCRIPT_PARSE_ERROR, 'Error while loading script "${path}", could not retrieve contents of non-existent script!');
			return null;
		}

		Polymod.assetLibrary.loadText(path).onComplete((text) ->
		{
			try
			{
				Polymod.debug('Fetched script class "$path", parsing...');
				registerScriptClassByString(text);
				promise.complete(true);
			}
			catch (err:PolymodExprEx.ErrorEx)
			{
				var errLine:String = #if hscriptPos '${err.line}' #else "#???" #end;
				#if hscriptPos
				switch (err.e)
				#else
				switch (err)
				#end
				{
					case EUnexpected(s):
						Polymod.error(SCRIPT_PARSE_ERROR,
							'Error while parsing script ${path}#${errLine}: EUnexpected' + '\n' +
							'Unexpected error: Unexpected token "${s}", is there invalid syntax on this line?');
					default:
						Polymod.error(SCRIPT_PARSE_ERROR,
							'Error while parsing script ${path}#${errLine}: ' + '\n' + 'An unknown error occurred: ${err}');
				}
				promise.error(err);
			}
		}).onError((err) ->
			{
				if (err == "404") {
					Polymod.error(SCRIPT_PARSE_ERROR, 'Error while loading script "${path}", could not retrieve script contents (404 error)!');
				} else {
					Polymod.error(SCRIPT_PARSE_ERROR, 'Error while parsing script ${path}: ' + '\n' + 'An unknown error occurred: ${err}');
					promise.error(err);
				}
			});
		// Await the promise
		return promise.future;
	}

	/**
	 * Returns a list of all registered classes.
	 * @return Array<String>
	 */
	public static function listScriptClasses():Array<String>
	{
		var result = [];
		@:privateAccess
		for (key => _value in PolymodInterpEx._scriptClassDescriptors)
		{
			result.push(key);
		}
		return result;
	}

	/**
	 * Clears all parsed scripted class descriptors.
	 * You can call `Polymod.registerAllScriptClasses()` to re-register them later.
	 */
	public static function clearScriptedClasses():Void {
		scriptInterp.clearScriptClassDescriptors();
	}

	/**
	 * Returns a list of all registered classes which extend the class specified by the given name.
	 * @return Array<String>
	 */
	public static function listScriptClassesExtending(clsPath:String):Array<String>
	{
		var result = [];
		@:privateAccess
		for (key => value in PolymodInterpEx._scriptClassDescriptors)
		{
			var superClasses = getSuperClasses(value);
			if (superClasses.indexOf(clsPath) != -1)
			{
				result.push(key);
			}
		}
		return result;
	}

	/**
	 * Returns a list of all registered classes which extend the specified class.
	 		* @param cls Any Class which you expect scripted classes to be extending.
	 * @return Array<String>
	 */
	static function listScriptClassesExtendingClass(cls:Class<Dynamic>):Array<String>
	{
		return listScriptClassesExtending(Type.getClassName(cls));
	}

	static function getSuperClasses(classDecl:PolymodClassDeclEx):Array<String>
	{
		if (classDecl.extend == null)
		{
			// No superclasses.
			return [];
		}

		// Get the super class name.
		var fullSuperClsName = (new hscript.Printer()).typeToString(classDecl.extend);
		var baseSuperClsName = switch(classDecl.extend) {
			case CTPath(pth, params):
				pth[pth.length - 1];
			default:
				fullSuperClsName;
		};

		// Check if the superclass is a scripted class.
		var classDescriptor:PolymodClassDeclEx = PolymodInterpEx.findScriptClassDescriptor(fullSuperClsName);

		if (classDescriptor != null)
		{
			var result = [fullSuperClsName];

			// Parse the parent scripted class.
			return result.concat(getSuperClasses(classDescriptor));
		}
		else
		{
			// Templates are ignored completely since there's no type checking in HScript.
			if (fullSuperClsName.indexOf('<') != -1)
			{
				fullSuperClsName = fullSuperClsName.split('<')[0];
				baseSuperClsName = baseSuperClsName.split('<')[0];
			}

			var superCls:Class<Dynamic> = null;

			if (classDecl.imports.exists(baseSuperClsName))
			{
				var importedClass:PolymodClassImport = classDecl.imports.get(baseSuperClsName);
				if (importedClass != null && importedClass.cls == null) {
					// importedClass was defined but `cls` was null. This class must have been blacklisted.
					var clsName = classDecl.pkg != null ? '${classDecl.pkg.join('.')}.${classDecl.name}' : classDecl.name;
					Polymod.error(SCRIPT_PARSE_ERROR, 'Could not parse superclass "${classDecl.name}" of scripted class "${clsName}". The superclass may be blacklisted.');
					return [];
				} else if (importedClass != null) {
					superCls = importedClass.cls;
				}
			}

			// Check if the superclass was resolved.
			if (superCls != null)
			{
				var result = [];
				// The superclass is a native class.
				while (superCls != null)
				{
					// Recursively add this class's superclasses.
					result.push(Type.getClassName(superCls));

					// This returns null when the class has no superclass.
					superCls = Type.getSuperClass(superCls);
				}
				return result;
			}
			else
			{
				// The superclass is not a scripted class or native class. Probably doesn't exist, throw an error.
				var clsName = classDecl.pkg != null ? '${classDecl.pkg.join('.')}.${classDecl.name}' : classDecl.name;
				Polymod.error(SCRIPT_PARSE_ERROR, 'Could not parse superclass "$fullSuperClsName" of scripted class "${clsName}". Did you forget to import it?');
				return [];
			}
		}
	}

	public static function callScriptClassStaticFunction(clsName:String, funcName:String, args:Array<Dynamic> = null):Dynamic {
		return scriptInterp.callScriptClassStaticFunction(clsName, funcName, args);
	}

	public static function hasScriptClassStaticFunction(clsName:String, funcName:String):Bool {
		return scriptInterp.hasScriptClassStaticFunction(clsName, funcName);
	}

	public static function getScriptClassStaticField(clsName:String, fieldName:String):Dynamic {
		return scriptInterp.getScriptClassStaticField(clsName, fieldName);
	}

	public static function setScriptClassStaticField(clsName:String, fieldName:String, fieldValue:Dynamic):Dynamic {
		return scriptInterp.setScriptClassStaticField(clsName, fieldName, fieldValue);
	}

	/**
	 * INSTANCE METHODS
	 */
	public function new(c:PolymodClassDeclEx, args:Array<Dynamic>)
	{
		var targetClass:Class<Dynamic> = null;
		switch (c.extend)
		{
			case CTPath(pth, params):
				var clsPath = pth.join('.');
				var clsName = pth[pth.length - 1];

				if (PolymodInterpEx.findScriptClassDescriptor(clsName) != null) {
					targetClass = null;
				}
				else if (scriptClassOverrides.exists(clsPath)) {
					targetClass = scriptClassOverrides.get(clsPath);
				}
				else if (c.imports.exists(clsName))
				{
					var importedClass:PolymodClassImport = c.imports.get(clsName);
					if (importedClass != null && importedClass.cls != null) {
						targetClass = importedClass.cls;
					} else if (importedClass != null && importedClass.cls == null) {
						Polymod.error(SCRIPT_PARSE_ERROR, 'Could not determine target class for "${pth.join('.')}" (blacklisted type?)');
					} else {
						Polymod.error(SCRIPT_PARSE_ERROR, 'Could not determine target class for "${pth.join('.')}" (unregistered type?)');
					}
				} else {
					Polymod.error(SCRIPT_PARSE_ERROR, 'Could not determine target class for "${pth.join('.')}" (unregistered type?)');
				}
			default:
				Polymod.error(SCRIPT_PARSE_ERROR, 'Could not determine target class for "${c.extend}" (unknown type?)');
		}
		_interp = new PolymodInterpEx(targetClass, this);
		_c = c;
		buildCaches();

		var ctorField = findField("new");
		if (ctorField != null)
		{
			callFunction("new", args);
			if (superClass == null && _c.extend != null)
			{
				@:privateAccess _interp.errorEx(EClassSuperNotCalled);
			}
		}
		else if (_c.extend != null)
		{
			createSuperClass(args);
		}
	}

	var __superClassFieldList:Array<String> = null;

	public function superHasField(name:String):Bool
	{
		if (superClass == null)
			return false;
		// Reflect.hasField(this, name) is REALLY expensive so we use a cache.
		if (__superClassFieldList == null)
		{
			__superClassFieldList = [];

			var _superClass = superClass;
			while (Std.isOfType(_superClass, PolymodScriptClass))
			{
				var scriptFields:Array<String> = [for (key in (_superClass._cachedFieldDecls?.keys() ?? [])) key.name];
				__superClassFieldList = __superClassFieldList.concat(scriptFields);

				_superClass = _superClass.superClass;
			}

			__superClassFieldList = __superClassFieldList.concat(Reflect.fields(_superClass));
			__superClassFieldList = __superClassFieldList.concat(Type.getInstanceFields(Type.getClass(_superClass)));
		}
		return __superClassFieldList.indexOf(name) != -1;
	}

	private function createSuperClass(args:Array<Dynamic> = null)
	{
		if (args == null)
		{
			args = [];
		}

		var fullExtendString = new hscript.Printer().typeToString(_c.extend);

		// Templates are ignored completely since there's no type checking in HScript.
		if (fullExtendString.indexOf('<') != -1)
		{
			fullExtendString = fullExtendString.split('<')[0];
		}

		// Build an unqualified path too.
		var fullExtendStringParts = fullExtendString.split('.');
		var extendString = fullExtendStringParts[fullExtendStringParts.length - 1];

		var classDescriptor = PolymodInterpEx.findScriptClassDescriptor(extendString);
		if (classDescriptor != null)
		{
			var abstractSuperClass:PolymodAbstractScriptClass = new PolymodScriptClass(classDescriptor, args);
			superClass = abstractSuperClass;
		}
		else
		{
			var clsToCreate:Class<Dynamic> = null;

			if (scriptClassOverrides.exists(fullExtendString)) {
				clsToCreate = scriptClassOverrides.get(fullExtendString);

				if (clsToCreate == null)
				{
					@:privateAccess _interp.errorEx(EClassUnresolvedSuperclass(fullExtendString, 'WHY?'));
				}
			} else if (_c.imports.exists(extendString)) {
				clsToCreate = _c.imports.get(extendString).cls;

				if (clsToCreate == null)
				{
					@:privateAccess _interp.errorEx(EClassUnresolvedSuperclass(extendString, 'target class blacklisted'));
				}
			} else {
				@:privateAccess _interp.errorEx(EClassUnresolvedSuperclass(extendString, 'missing import'));
			}

			superClass = Type.createInstance(clsToCreate, args);
		}

		// Throw an error if the script class has an instance field with the same name as one from the super class.
		for (f in _c.fields)
		{
			switch (f.kind)
			{
				case KVar(v):
					if (!f.access.contains(AStatic) && superHasField(f.name))
					{
						throw 'Redefinition of variable "${f.name}" from superclass not allowed';
					}

				case _:
			}
		}
	}

	public static function reportError(err:hscript.Expr.Error, className:String = null, fnName:String = null)
	{
		var errEx = PolymodExprEx.ErrorExUtil.toErrorEx(err);
		reportErrorEx(errEx, className, fnName);
	}

	public static function reportErrorEx(err:PolymodExprEx.ErrorEx, className:String = null, fnName:String = null):Void
	{
		var errLine:String = #if hscriptPos '${err.line}' #else "#???" #end;

		className ??= '???';
		fnName ??= 'anonymous';

		#if hscriptPos
		switch (err.e)
		#else
		switch (err)
		#end
		{
			// EInvalidChar
			// EUnexpected
			// EUnterminatedString
			// EUnterminatedComment
			// EInvalidPreprocessor
			// EInvalidIterator
			// EInvalidOp
			case ECustom(msg):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' + 'An unknown error occurred: ${msg}');
			case EClassUnresolvedSuperclass(c, r):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' + 'Could not resolve super class type "${c}" (${r})');
			case EClassSuperNotCalled:
					Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
						'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' + 'Custom constructor does not call "super()".');
			case EInvalidScriptedFnAccess(f):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' +
					'Could not call function "${f}" on scripted class. Did you try obj.scriptCall("${f}", [...])?');
			case EInvalidInStaticContext(v):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' +
					'Cannot access value "${v}" from a static context.');
			case EInvalidScriptedVarGet(v):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' +
					'Could not retrieve variable "${v}" on scripted class. Did you try obj.scriptGet("${v}")?');
			case EInvalidScriptedVarSet(v):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' +
					'Could not assign variable "${v}" on scripted class. Did you try obj.scriptSet("${v}", value)?');
			case EInvalidModule(m):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' + 'Could not resolve imported module type "${m}".');
			case EBlacklistedModule(m):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' + 'Imported module "${m}" has been blacklisted.');
			case EPurgedFunction(f):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' + 'Attempted to call purged function "${f}", did it throw an uncaught exception earlier?');
			case EUnknownVariable(v):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}:' + '\n' +
					'Tried to access "${v}", an unknown variable or identifier.');
			case EInvalidFinalSet(f):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}:' + '\n' +
					'Could not assign variable "${f}" because it is a final field.');
			case EInvalidAccess(f):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}:' + '\n' +
					'Tried to access "${f}", but it is not a valid field or method. Is the target object null?');
			case EInvalidPropGet(p):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}:' + '\n' +
					'Property "${p}" is not accessible for reading.');
			case EInvalidPropSet(p):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}:' + '\n' +
					'Property "${p}" is not accessible for writing.');
			case EPropVarNotReal(p):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}:' + '\n' +
					'Property "${p}" cannot be accessed because it is not a real variable. Add @:isVar to enable it.');
			case EScriptThrow(v):
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}:' + '\n' +
					'User script threw an error: ${v}');
			default:
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' + 'An unknown error occurred: ${err}');
		}
	}

	@:privateAccess(hscript.Interp)
	public function callFunction(fnName:String, args:Array<Dynamic> = null):Dynamic
	{
		var field = findField(fnName);
		var fn = (field != null) ? findFunction(fnName, true) : null;

		if (fn != null)
		{
			// previousValues is used to restore variables after they are shadowed in the local scope.
			var previousValues:Map<String, Dynamic> = [];
			var i = 0;
			for (a in fn.args)
			{
				var value:Dynamic = null;

				if (args != null && i < args.length)
				{
					value = args[i];
				}
				else if (a.value != null)
				{
					value = _interp.expr(a.value);
				}

				// NOTE: We assign these as variables rather than locals because those get wiped when we enter the function.
				if (_interp.variables.exists(a.name))
				{
					previousValues.set(a.name, _interp.variables.get(a.name));
				}
				_interp.variables.set(a.name, value);
				i++;
			}

			// Polymod.debug('Calling scripted class function "${fullyQualifiedName}.${fnName}(${args})"', null);

			// Copy the locals and store them for later.
			var localsCopy:Map<String, {r:Dynamic, ?isfinal:Null<Bool>}> = _interp.locals.copy();

			var r:Dynamic = null;
			try
			{
				r = _interp.executeEx(fn.expr);
			}
			catch (err:PolymodExprEx.ErrorEx)
			{
				reportErrorEx(err, fullyQualifiedName, fnName);
				// A script error occurred while executing the script function.
				// Purge the function from the cache so it is not called again.
				purgeFunction(fnName);
			}
			catch (err:hscript.Expr.Error)
			{
				reportError(err, fullyQualifiedName, fnName);
				// A script error occurred while executing the script function.
				// Purge the function from the cache so it is not called again.
				purgeFunction(fnName);
			}

			// This NEEDS to run regardless of the function succeeding or not, or else the previous values might be lost.
			for (a in fn.args)
			{
				if (previousValues.exists(a.name))
				{
					_interp.variables.set(a.name, previousValues.get(a.name));
				}
				else
				{
					_interp.variables.remove(a.name);
				}
			}

			// Restore the locals.
			_interp.locals = localsCopy;

			return r;
		}
		else
		{
			var fn = findSuperFunction(fnName);
			if (fn == null)
			{
				Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
					'Error while calling function ${fnName}(): EInvalidAccess' + '\n' +
					'Script does not have function "${fnName}"! Define it or call the correct script function or superclass function.');
				return null;
			}

			var fixedArgs = (args?.length == 0) ? args : args.map((a) -> {
				if (Std.isOfType(a, PolymodScriptClass))
				{
					return cast(a, PolymodScriptClass).superClass;
				}
				else
				{
					return a;
				}
			});

			return Reflect.callMethod(superClass, fn, fixedArgs);
		}
	}

	/**
	 * Checks if the class has a script function with the given name.
	 * This is useful for checking whether the game should simply call the superclass function directly.
	 * @param name The name of the function to check.
	 * @return `true` if the class has a script function with the given name, `false` otherwise.
	 */
	public function hasScriptFunction(name:String):Bool {
		var field = findField(name);
		var fn = (field != null) ? findFunction(name, true) : null;

		return fn != null;
	}

	private var _c:PolymodClassDeclEx;
	private var _interp:PolymodInterpEx;

	public var superClass:Dynamic = null;

	public var fullyQualifiedName(get, null):String;

	private function get_fullyQualifiedName():String
	{
		var name = "";
		if (_c.pkg != null && _c.pkg.length > 0)
		{
			name += (_c.pkg?.join(".") ?? '') + ".";
		}
		name += _c.name;
		return name;
	}

	private inline function callFunction0(name:String):Dynamic
	{
		return callFunction(name);
	}

	private inline function callFunction1(name:String, arg0:Dynamic):Dynamic
	{
		return callFunction(name, [arg0]);
	}

	private inline function callFunction2(name:String, arg0:Dynamic, arg1:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1]);
	}

	private inline function callFunction3(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2]);
	}

	private inline function callFunction4(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2, arg3]);
	}

	private inline function callFunction5(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4]);
	}

	private inline function callFunction6(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic, arg5:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4, arg5]);
	}

	private inline function callFunction7(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic, arg5:Dynamic,
			arg6:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4, arg5, arg6]);
	}

	private inline function callFunction8(name:String, arg0:Dynamic, arg1:Dynamic, arg2:Dynamic, arg3:Dynamic, arg4:Dynamic, arg5:Dynamic, arg6:Dynamic,
			arg7:Dynamic):Dynamic
	{
		return callFunction(name, [arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7]);
	}

	/**
	 * Search for a function field with the given name. Excludes variables and static functions.
	 * @param name The name of the function to search for.
	 * @param cacheOnly If false, scan the full list of fields.
	 *                  If true, ignore uncached fields.
	 * @param excludeStatic If true, exclude static fields.
	 */
	private function findFunction(name:String, cacheOnly:Bool = true, excludeStatic:Bool = true):Null<FunctionDecl>
	{
		if (_cachedFunctionDecls != null && _cachedFunctionDecls.exists(name))
		{
			return _cachedFunctionDecls.get(name);
		}
		if (cacheOnly) return null;

		var fn = findField(name);
		if (fn == null) return null;
		switch (fn.kind) {
			case KFunction(func):
				if (excludeStatic && fn.access.contains(AStatic)) return null;
				_cachedFunctionDecls.set(name, func);
				return func;
			default:
				return null;
		}
	}

	/**
	 * Search for a function field on the superclass with the given name.
	 */
	private function findSuperFunction(name:String):Null<Dynamic>
	{
		if (_cachedSuperFunctionDecls != null && _cachedSuperFunctionDecls.exists(name))
		{
			return _cachedSuperFunctionDecls.get(name);
		}

		if (Std.isOfType(superClass, PolymodScriptClass))
		{
			var func = Reflect.field(superClass, name);
			if (func == null) return null;

			_cachedSuperFunctionDecls.set(name, func);
			return func;
		}

		// OVERRIDE CHANGE: Use __super_ when calling superclass
		var fixedName = '__super_${name}';

		var func = Reflect.field(superClass, fixedName);
		if (func == null) return null;
		_cachedSuperFunctionDecls.set(name, func);
		return func;
	}

	/**
	 * Remove a function from the cache.
	 * This is useful when a function is broken and needs to be skipped.
	 * @param name The name of the function to remove from the cache.
	 */
	private function purgeFunction(name:String):Void {
		if (_cachedFunctionDecls != null)
		{
			_cachedFunctionDecls.remove(name);
		}
	}

	/**
	 * Search for a variable field with the given name. Excludes functions and static variables.
	 * @param name The name of the variable to search for.
	 * @param cacheOnly If false, scan the full list of fields.
	 *                  If true, ignore uncached fields.
	 * @param excludeStatic If true, exclude static fields.
	 */
	private function findVar(name:String, cacheOnly:Bool = false, excludeStatic:Bool = true):Null<VarDecl>
	{
		if (_cachedVarDecls != null && _cachedVarDecls.exists(name))
		{
			return _cachedVarDecls.get(name);
		}
		if (cacheOnly) return null;

		for (f in _c.fields)
		{
			if (f.name == name)
			{
				switch (f.kind)
				{
					case KVar(v):
						if (excludeStatic && f.access.contains(AStatic)) return null;
						_cachedVarDecls?.set(name, v);
						return v;
					case _:
				}
			}
		}

		return null;
	}

	/**
	 * Search for a field (function OR variable) with the given name.
	 * @param name The name of the field to search for.
	 * @param cacheOnly If false, scan the full list of fields.
	 *                  If true, ignore uncached fields.
	 */
	private function findField(name:String, cacheOnly:Bool = true):Null<FieldDecl>
	{
		if (_cachedFieldDecls != null && _cachedFieldDecls.exists(name))
		{
			return _cachedFieldDecls.get(name);
		}
		if (cacheOnly) return null;

		for (f in _c.fields)
		{
			if (f.name == name)
			{
				return f;
			}
		}
		return null;
	}

	public function listFunctions():Map<String, FunctionDecl>
	{
		return _cachedFunctionDecls;
	}

	private var _cachedFieldDecls:Map<String, FieldDecl> = [];
	private var _cachedSuperFunctionDecls:Map<String, Dynamic> = [];
	private var _cachedFunctionDecls:Map<String, FunctionDecl> = [];
	private var _cachedVarDecls:Map<String, VarDecl> = [];
	private var _cachedUsingFunctions:Map<String, Dynamic> = [];

	private function buildCaches()
	{
		_cachedFieldDecls.clear();
		_cachedSuperFunctionDecls.clear();
		_cachedFunctionDecls.clear();
		_cachedVarDecls.clear();
		_cachedUsingFunctions.clear();

		for (n => u in _c.usings)
		{
			var fields = Type.getClassFields(u.cls);
			if (fields.length == 0) continue;

			for (fld in fields)
			{
				var func:Dynamic = function(params:Array<Dynamic>)
				{
					var prop:Dynamic = Reflect.getProperty(u.cls, fld);
					return Reflect.callMethod(u.cls, prop, params);
				}

				_cachedUsingFunctions.set(fld, func);
			}
		}

		for (f in _c.fields)
		{
			if (_cachedFieldDecls.exists(f.name)) {
				throw 'Duplicate field name "${f.name}" in class "${_c.name}"';
			}

			_cachedFieldDecls.set(f.name, f);
			switch (f.kind)
			{
				case KFunction(fn):
					_cachedFunctionDecls.set(f.name, fn);
				case KVar(v):
					_cachedVarDecls.set(f.name, v);
					if (v.expr != null)
					{
						var varValue = this._interp.expr(v.expr);
						this._interp.variables.set(f.name, varValue);
					}
				default:
					throw 'Unknown field kind: ${f.kind}';
			}
		}
	}
}
#end
