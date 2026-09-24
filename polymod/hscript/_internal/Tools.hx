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

import polymod.hscript._internal.Expr;

class Tools
{
  public static function iter(e:Expr, f:Expr->Void)
  {
    switch (expr(e))
    {
      case EConst(_), EIdent(_):
      case EVar(_, _, e) | EFinal(_, _, e):
        if (e != null) f(e);
      case EParent(e):
        f(e);
      case EBlock(el):
        for (e in el)
          f(e);
      case EField(e, _):
        f(e);
      case EBinop(_, e1, e2):
        f(e1);
        f(e2);
      case EUnop(_, _, e):
        f(e);
      case ECall(e, args):
        f(e);
        for (a in args)
          f(a);
      case EIf(c, e1, e2):
        f(c);
        f(e1);
        if (e2 != null) f(e2);
      case EWhile(c, e):
        f(c);
        f(e);
      case EDoWhile(c, e):
        f(c);
        f(e);
      case EFor(_, it, e):
        f(it);
        f(e);
      case EForGen(it, e):
        f(it);
        f(e);
      case EBreak, EContinue:
      case ECast(e, _):
        f(e);
      case EFunction(_, e, _, _):
        f(e);
      case EReturn(e):
        if (e != null) f(e);
      case EArray(e, i):
        f(e);
        f(i);
      case EArrayDecl(el):
        for (e in el)
          f(e);
      case ENew(_, el):
        for (e in el)
          f(e);
      case EThrow(e):
        f(e);
      case ETry(e, _, _, c):
        f(e);
        f(c);
      case EObject(fl):
        for (fi in fl)
          f(fi.e);
      case ETernary(c, e1, e2):
        f(c);
        f(e1);
        f(e2);
      case ESwitch(e, cases, def):
        f(e);
        for (c in cases)
        {
          for (v in c.values)
            f(v);
          f(c.expr);
        }
        if (def != null) f(def);
      case EMeta(name, args, e):
        if (args != null) for (a in args)
          f(a);
        f(e);
      case ECheckType(e, _):
        f(e);
    }
  }

  /**
   * `EnumValueTools.equals` doesn't work with `Expr` so we have to manually do it.
   * Thankfully not every Expr is used in a case so we don't have to check for everything.
   * @param e1 The first expression to check
   * @param e2 The second expression to check
   * @return Whether the expressions are recursively equal.
   */
  public static function switchExprEquals(e1:ExprDef, e2:ExprDef):Bool
  {
    switch (e1)
    {
      case EConst(c):
        switch (e2)
        {
          case EConst(c2):
            return c.equals(c2);
          default:
            return false;
        }
      case EIdent(v1):
        switch (e2)
        {
          case EIdent(v2): return v1 == v2;
          default: return false;
        }
      case EVar(n, t, e):
        switch (e2)
        {
          case EVar(n2, t2, e2):
            return n == n2 && t.equals(t2) && switchExprEquals(expr(e), expr(e2));
          default: return false;
        }
      case EFinal(n, t, e):
        switch (e2)
        {
          case EFinal(n2, t2, e2):
            return n == n2 && Type.enumEq(t, t2) && switchExprEquals(expr(e), expr(e2));
          default: return false;
        }
      case EParent(e):
        switch (e2)
        {
          case EParent(e2):
            return switchExprEquals(expr(e), expr(e2));
          default: return false;
        }
      case EBlock(e):
        switch (e2)
        {
          case EBlock(e2):
            if (e.length != e2.length)
              return false;

            for (i in 0...e.length)
            {
              if (!switchExprEquals(expr(e[i]), expr(e2[i])))
                return false;
            }
            return true;
          default:
            return false;
        }
      case EField(e, f):
        switch (e2)
        {
          case EField(e2, f2):
            if (!switchExprEquals(expr(e), expr(e2))) return false;
            if (f != f2) return false;
            return true;
          default:
            return false;
        }
      case EBinop(op, expr1, expr2):
        switch (e2)
        {
          case EBinop(op2, e2_1, e2_2):
            if (!switchExprEquals(expr(expr1), expr(e2_1))) return false;
            if (!switchExprEquals(expr(expr2), expr(e2_2))) return false;
            if (op != op2) return false;

            return true;
          default:
            return false;
        }
      case EUnop(op, prefix, e):
        switch (e2)
        {
          case EUnop(op2, prefix2, e2):
            if (op != op2) return false;
            if (prefix != prefix2) return false;
            if (!switchExprEquals(expr(e), expr(e2))) return false;

            return true;
          default:
            return false;
        }
      case ECall(e, params):
        switch (e2)
        {
          case ECall(e2, params2):
            if (params.length != params2.length) return false;

            for (i in 0...params2.length)
            {
              if (!switchExprEquals(expr(params[i]), expr(params2[i]))) return false;
            }
            if (!switchExprEquals(expr(e), expr(e2))) return false;
            return true;
          default:
            return false;
        }
      case ECast(e, t):
        switch (e2)
        {
          case ECast(e2, t2):
            if (!switchExprEquals(expr(e), expr(e2))) return false;
            if (t != null && t.equals(t2)) return false;
            return true;
          default:
            return false;
        }
      case EArray(e, index):
        switch (e2)
        {
          case EArray(e2, index2):
            if (!switchExprEquals(expr(e), expr(e2))) return false;
            if (!switchExprEquals(expr(index), expr(index2))) return false;

            return true;
          default:
            return false;
        }
      case EArrayDecl(e):
        switch (e2)
        {
          case EArrayDecl(e2):
            if (e.length != e2.length) return false;

            for (i in 0...e.length)
            {
              if (!switchExprEquals(expr(e[i]), expr(e2[i]))) return false;
            }
            return true;
          default:
            return false;
        }
      case EObject(fl):
        switch (e2)
        {
          case EObject(fl2):
            if (fl.length != fl2.length) return false;

            for (i in 0...fl.length)
            {
              if (fl[i].name != fl2[i].name) return false;
              if (!switchExprEquals(expr(fl[i].e), expr(fl2[i].e))) return false;
            }
            return true;
          default:
            return false;
        }
      default:
        return false;
    }
  }

  public static function map(e:Expr, f:Expr->Expr)
  {
    var edef = switch (expr(e))
    {
      case EConst(_), EIdent(_), EBreak, EContinue: expr(e);
      case ECast(e, t): ECast(f(e), t);
      case EVar(n, t, e): EVar(n, t, if (e != null) f(e) else null);
      case EFinal(n, t, e): EFinal(n, t, if (e != null) f(e) else null);
      case EParent(e): EParent(f(e));
      case EBlock(el): EBlock([for (e in el) f(e)]);
      case EField(e, fi): EField(f(e), fi);
      case EBinop(op, e1, e2): EBinop(op, f(e1), f(e2));
      case EUnop(op, pre, e): EUnop(op, pre, f(e));
      case ECall(e, args): ECall(f(e), [for (a in args) f(a)]);
      case EIf(c, e1, e2): EIf(f(c), f(e1), if (e2 != null) f(e2) else null);
      case EWhile(c, e): EWhile(f(c), f(e));
      case EDoWhile(c, e): EDoWhile(f(c), f(e));
      case EFor(v, it, e): EFor(v, f(it), f(e));
      case EForGen(it, e): EForGen(f(it), f(e));
      case EFunction(args, e, name, t): EFunction(args, f(e), name, t);
      case EReturn(e): EReturn(if (e != null) f(e) else null);
      case EArray(e, i): EArray(f(e), f(i));
      case EArrayDecl(el): EArrayDecl([for (e in el) f(e)]);
      case ENew(cl, el): ENew(cl, [for (e in el) f(e)]);
      case EThrow(e): EThrow(f(e));
      case ETry(e, v, t, c): ETry(f(e), v, t, f(c));
      case EObject(fl): EObject([for (fi in fl) {name: fi.name, e: f(fi.e)}]);
      case ETernary(c, e1, e2): ETernary(f(c), f(e1), f(e2));
      case ESwitch(e, cases, def): ESwitch(f(e), [for (c in cases) {values: [for (v in c.values) f(v)], guard: (c.guard == null ? null : f(c.guard)), expr: f(c.expr)}], def == null ? null : f(def));
      case EMeta(name, args, e): EMeta(name, args == null ? null : [for (a in args) f(a)], f(e));
      case ECheckType(e, t): ECheckType(f(e), t);
    }
    return mk(edef, e);
  }

  public static inline function expr(e:Expr):ExprDef
  {
    #if hscriptPos
    return e.e;
    #else
    return e;
    #end
  }

  public static inline function mk(e:ExprDef, p:Expr)
  {
    #if hscriptPos
    return {
      e: e,
      pmin: p.pmin,
      pmax: p.pmax,
      origin: p.origin,
      line: p.line
    };
    #else
    return e;
    #end
  }

  public static inline function getKeyIterator<T>(e:Expr, callb:String->String->Expr->T)
  {
    var key = null, value = null, it = e;
    switch (expr(it))
    {
      case EBinop("in", ekv, eiter):
        switch (expr(ekv))
        {
          case EBinop("=>", v1, v2):
            switch ([expr(v1), expr(v2)])
            {
              case [EIdent(v1), EIdent(v2)]:
                key = v1;
                value = v2;
                it = eiter;
              default:
            }
          default:
        }
      default:
    }
    return callb(key, value, it);
  }
}
