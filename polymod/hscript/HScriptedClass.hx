package polymod.hscript;

/**
 * This interface triggers the execution of a macro which redirects all function calls to a scripted class.
 */
@:autoBuild(polymod.hscript._internal.HScriptedClassMacro.build())
interface HScriptedClass
{
  // The following functions ARE REAL, and are generated and applied to any class that implements this interface.
  // I attempted to uncomment the below functions previously, and spent a good chunk of time tackling it,
  // but found that cyclic dependencies resulted (building some methods of the class relies on building other classes,
  // and those classes rely on the scripted class functions having already been defined).
  //
  // The alternatives are using expensive reflection or adding a verbose warning, and I chose the latter.
  //
  // STATIC METHODS
  //
  /**
   * Initialize an instance of this scripted class.
   *
   * @param clsName The full classpath of the scripted class to instantiate.
   * @param constArgs The arguments to pass to the constructor.
   * @return The instance of the scripted class.
   */
  // public static function scriptInit(clsName:String, ...constArgs:Dynamic):ThisType;
  /**
   * Call a custom static function on a scripted class, by the given name, with the given arguments.
   *
   * @param clsName The full classpath of the scripted class to invoke on.
   * @param funcName The name of the function to call.
   * @param funcArgs The arguments to pass to the function.
   * @return The result of the function call.
   */
  // public static function scriptStaticCall(clsName:String, funcName:String, funcArgs:Array<Dynamic>):Dynamic;
  /**
   * Retrieves a custom static variable on a scripted class, by the given name.
   *
   * @param clsName The full classpath of the scripted class to invoke on.
   * @param fieldName The name of the variable to retrieve.
   * @return The value of the variable.
   */
  // public static function scriptStaticGet(clsName:String, fieldName:String):Dynamic;
  /**
   * Sets the value of a custom static variable on a scripted class, by the given name.
   *
   * @param clsName The full classpath of the scripted class to invoke on.
   * @param fieldName The name of the variable to set.
   * @param value The value to set.
   * @return The newly set value.
   */
  // public static function scriptStaticSet(clsName:String, fieldName:String, value:Dynamic):Dynamic;
  //
  // INSTANCE METHODS
  //
  /**
   * Call a custom instance function on a scripted class, by the given name, with the given arguments.
   *
   * @param funcName The name of the function to call.
   * @param funcArgs The arguments to pass to the function.
   * @return The result of the function call.
   */
  // public function scriptCall(funcName:String, funcArgs:Array<Dynamic>):Dynamic;
  /**
   * Returns the value of a custom instance field of the scripted class, by the given name.
   *
   * @param fieldName The name of the field to return.
   * @return The value of the field, if any.
   */
  // public function scriptGet(fieldName:String):Dynamic;
  /**
   * Sets the value of a custom field of the scripted class, by the given name.
   *
   * @param fieldName The name of the field to set.
   * @param value The value to set.
   * @return The newly set value.
   */
  // public function scriptSet(fieldName:String, value:Dynamic):Dynamic;
  /**
   * Returns whether the field exists on a scripted class (or its superclass).
   *
   * @param fieldName The name of the field to query.
   * @return Whether the field exists.
   */
  // public function scriptHas(fieldName:String):Bool;
}
