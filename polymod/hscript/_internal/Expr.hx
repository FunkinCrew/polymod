/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package polymod.hscript._internal;

enum Const
{
  CInt(v:Int);
  CFloat(f:Float);
  CString(s:String, ?interpolated:Bool);
}

#if hscriptPos
typedef Expr =
{
  var e:ExprDef;
  var pmin:Int;
  var pmax:Int;
  var origin:String;
  var line:Int;
}

enum ExprDef
#else
typedef ExprDef = Expr;

enum Expr
#end
{
  EConst(c:Const);
  EIdent(v:String);
  EVar(n:String, ?t:CType, ?e:Expr);
  EFinal(n:String, ?t:CType, ?e:Expr);
  EParent(e:Expr);
  EBlock(e:Array<Expr>);
  EField(e:Expr, f:String);
  EBinop(op:String, e1:Expr, e2:Expr);
  EUnop(op:String, prefix:Bool, e:Expr);
  ECall(e:Expr, params:Array<Expr>);
  EIf(cond:Expr, e1:Expr, ?e2:Expr);
  EWhile(cond:Expr, e:Expr);
  EFor(v:String, it:Expr, e:Expr);
  EBreak;
  EContinue;
  EFunction(args:Array<Argument>, e:Expr, ?name:String, ?ret:CType);
  EReturn(?e:Expr);
  EArray(e:Expr, index:Expr);
  EArrayDecl(e:Array<Expr>);
  ENew(cl:String, params:Array<Expr>);
  EThrow(e:Expr);
  ETry(e:Expr, v:String, t:Null<CType>, ecatch:Expr);
  EObject(fl:Array<{name:String, e:Expr}>);
  ETernary(cond:Expr, e1:Expr, e2:Expr);
  ESwitch(e:Expr, cases:Array<{values:Array<Expr>, expr:Expr}>, ?defaultExpr:Expr);
  EDoWhile(cond:Expr, e:Expr);
  EMeta(name:String, args:Array<Expr>, e:Expr);
  ECheckType(e:Expr, t:CType);
  EForGen(it:Expr, e:Expr);
}

typedef Argument =
{
  name:String,
  ?t:CType,
  ?opt:Bool,
  ?value:Expr
};

typedef Metadata = Array<{name:String, params:Array<Expr>}>;

enum CType
{
  CTPath(path:Array<String>, ?params:Array<CType>);
  CTFun(args:Array<CType>, ret:CType);
  CTAnon(fields:Array<{name:String, t:CType, ?meta:Metadata}>);
  CTParent(t:CType);
  CTOpt(t:CType);
  CTNamed(n:String, t:CType);
  CTExpr(e:Expr); // for type parameters only
}

#if hscriptPos
/**
 * Stores information about an error.
 */
class Error
{
  /**
   * The error type.
   */
  public var e:ErrorDef;

  /**
   * Start position in the code where this error occurred.
   */
  public var pmin:Int;

  /**
   * End position in the code where this error occurred.
   */
  public var pmax:Int;

  /**
   * The origin of where the error occurred.
   * This is usually the file name.
   */
  public var origin:String;

  /**
   * The line number the error occurred on.
   */
  public var line:Int;

  public function new(e, pmin, pmax, origin, line)
  {
    this.e = e;
    this.pmin = pmin;
    this.pmax = pmax;
    this.origin = origin;
    this.line = line;
  }

  public function toString():String
  {
    return Printer.errorToString(this);
  }
}

enum ErrorDef
#else
enum Error
#end
{
  EInvalidChar(c:Int);
  EUnexpected(s:String);
  EUnterminatedString;
  EUnterminatedComment;
  EInvalidPreprocessor(msg:String);
  EUnknownVariable(v:String);
  EInvalidIterator(v:String);
  EInvalidOp(op:String);
  EInvalidAccess(f:String);
  EInvalidModule(m:String);
  EBlacklistedModule(m:String);
  EBlacklistedField(f:String);
  EPurgedFunction(f:String); // Function can't be called because it previously threw an uncaught exception
  EInvalidArgCount(f:String, expected:Int, given:Int); // Given arguments count don't match the minimum required parameters
  EExceedArgsCount(f:String, allowed:Int, passed:Int); // Provided arguments exceed the maximum allowed parameter count
  ENullObjectReference(f:String); // Accessing a field of "null"
  EInvalidScriptedFnAccess(f:String);
  EInvalidScriptedVarGet(v:String);
  EInvalidScriptedVarSet(v:String);
  EInvalidFinalSet(f:String);
  EInvalidPropGet(p:String); // Accessing a never/null getter
  EInvalidPropSet(p:String); // Accessing a never/null setter
  EPropVarNotReal(p:String); // Getter/setter accessing a (get/never,set/never) property within itself without "@:isVar"
  EInvalidInStaticContext(v:String); // Accessing "this" or "super" in a static function
  EClassSuperNotCalled;
  EClassUnresolvedSuperclass(c:String, r:String); // superclass and reason
  EClassInvalidSuper; // Accessing "super" in a parentless class
  EScriptThrow(v:Dynamic); // Script called "throw"
  EScriptCallThrow(v:Dynamic); // Script called a function which threw
  // Fallback error type.
  ECustom(msg:String);
}

enum ModuleDecl
{
  DPackage(path:Array<String>);
  DImport(path:Array<String>, ?everything:Bool, ?name:String);
  DUsing(path:Array<String>);
  DClass(c:ClassDecl);
  DTypedef(c:TypeDecl);
  DEnum(e:EnumDecl);
  DInterface(e:InterfaceDecl);
}

typedef ModuleType =
{
  var name:String;
  var params:{}; // TODO : not yet parsed
  var meta:Metadata;
  var isPrivate:Bool;
}

/**
 * A scripted class declaration, with a package declaration, imports, and potentially static fields.
 */
typedef ClassDecl =
{
  > ModuleType,

  /**
   * The type being extended by the scripted class
   */
  var extend:Null<CType>;

  /**
   * The interfaces being implemented by the scripted class
   */
  var implement:Array<CType>;

  /**
   * The static fields of the scripted class
   */
  var staticFields:Array<FieldDecl>;

  /**
   * The instance fields of the scripted class
   */
  var fields:Array<FieldDecl>;

  /**
   * Whether the class was declared with the `extern` keyword
   */
  var isExtern:Bool;

  /**
   * The package that the scripted class belongs to
   */
  var pkg:Array<String>;

  /**
   * The classes imported by the scripted class
   * This gets resolved at interpretation time to save performance and improve sandboxing
   */
  var imports:Map<String, ClassImport>;

  /**
   * The static extensions used by the scripted class
   * For example, `using StringTools` lets you call `String.replace` on a string directly.
   */
  var usings:Map<String, ClassImport>;

  /**
   * A list of imports that have yet to be validated
   *
   * Scripted classes that import other scripted classes might be parsed before the class they import,
   * so imports have to be done in two passes.
   */
  var importsToValidate:Map<String, ClassImport>;
}

/**
 * An imported class or enumeration.
 */
typedef ClassImport =
{
  /**
   * The name of the imported class
   */
  var name:String;

  /**
   * The package that the imported class belongs to
   */
  var pkg:Array<String>;

  /**
   * The full path of the imported class, including the package
   */
  var fullPath:String; // pkg.pkg.pkg.name

  /**
   * The underlying class that was imported.
   * Will be `null` if this is not a class (see `enm` or `abs`),
   * or the class the script tried to import was BLACKLISTED.
   */
  var ?cls:Class<Dynamic>;

  /**
   * The underlying enum that was imported.
   * Will be `null` if this is not an enum.
   */
  var ?enm:Enum<Dynamic>;

  /**
   * The underlying abstract class that was imported.
   * Will be `null` if this is not an abstract class.
   */
  var ?abs:PolymodStaticAbstractReference;
}

typedef EnumDecl =
{
  > ModuleType,
  var fields:Array<EnumFieldDecl>;
}

typedef EnumFieldDecl =
{
  var name:String;
  var args:Array<EnumArgDecl>;
}

typedef EnumArgDecl =
{
  var name:String;
  var type:Null<CType>;
}

typedef TypeDecl =
{
  > ModuleType,
  var extensions:Array<CType>;
  var t:CType;
}

typedef InterfaceDecl =
{
  > ModuleType,
  var extend:Array<CType>;
  var fields:Array<FieldDecl>;
  var isExtern:Bool;
}

typedef FieldDecl =
{
  var name:String;
  var meta:Metadata;
  var kind:FieldKind;
  var access:Array<FieldAccess>;
}

enum FieldAccess
{
  APublic;
  APrivate;
  AInline;
  AOverride;
  AStatic;
  AMacro;
}

enum FieldKind
{
  KFunction(f:FunctionDecl);
  KVar(v:VarDecl);
}

typedef FunctionDecl =
{
  var args:Array<Argument>;
  var expr:Expr;
  var ret:Null<CType>;
}

typedef VarDecl =
{
  var get:Null<String>;
  var set:Null<String>;
  var expr:Null<Expr>;
  var type:Null<CType>;
  var isfinal:Null<Bool>;
}
