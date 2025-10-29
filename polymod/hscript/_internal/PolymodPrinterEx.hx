package polymod.hscript._internal;

import hscript.Printer;

class PolymodPrinterEx extends Printer
{
	public static function errorExToString(e:PolymodExprEx.ErrorEx)
	{
		var message = switch (#if hscriptPos e.e #else e #end)
		{
			case EInvalidChar(c): "Invalid character: '" + (StringTools.isEof(c) ? "EOF" : String.fromCharCode(c)) + "' (" + c + ")";
			case EUnexpected(s): "Unexpected token: \"" + s + "\"";
			case EUnterminatedString: "Unterminated string";
			case EUnterminatedComment: "Unterminated comment";
			case EInvalidPreprocessor(str): "Invalid preprocessor (" + str + ")";
			case EUnknownVariable(v): "Unknown variable: " + v;
			case EInvalidIterator(v): "Invalid iterator: " + v;
			case EInvalidOp(op): "Invalid operator: " + op;
			case EInvalidAccess(f): "Invalid access to field " + f;
			case EInvalidPropGet(p): "Cannot access property " + p + " for reading";
			case EInvalidPropSet(p): "Cannot access property " + p + " for writing";
			case EPropVarNotReal(p): "Cannot access property " + p + " because it is not a real variable";
			case EInvalidModule(m): "Invalid module: " + m;
			case EBlacklistedModule(m): "Blacklisted module: " + m;
			case EInvalidInStaticContext(v): "Invalid field access from static context: " + v;
			case EInvalidScriptedFnAccess(f): "Invalid function access to scripted class: " + f;
			case EInvalidScriptedVarGet(v): "Invalid variable retrieval to scripted class: " + v;
			case EInvalidScriptedVarSet(v): "Invalid variable assignment to scripted class: " + v;
			case EInvalidFinalSet(f): "Invalid final field assignment: " + f;
			case EClassSuperNotCalled: "Super constructor not called";
			case EClassUnresolvedSuperclass(c, r): 'Unresolved superclass $c (reason: $r)';
			// TODO: Do we need to distinguish these?
			case EScriptCallThrow(v): "Script threw an exception: \n" + v;
			case EScriptThrow(v): "Script threw an exception: \n" + v;
			case ECustom(msg): msg;
		};
		#if hscriptPos
		return e.origin + ":" + e.line + ": " + message;
		#else
		return message;
		#end
	}
}
