package polymod.util;

import thx.semver.Version;
import thx.semver.VersionRule;

using Lambda;

/**
 * Remember, increment the patch version (1.0.x) if you make a bugfix,
 * increment the minor version (1.x.0) if you make a new feature (but previous content is still compatible),
 * and increment the major version (x.0.0) if you make a breaking change (e.g. new API or reorganized file format).
 */
class VersionUtil
{
  public static final DEFAULT_VERSION:Version = "1.0.0";
  public static final DEFAULT_VERSION_RULE:VersionRule = "*.*.*";

  /**
   * Validate `version` against `rule`.
   * @return true if `version` satisfies `rule`, false otherwise.
   */
  public static inline function match(version:Version, rule:VersionRule):Bool
  {
    if (version == null || rule == null) return false;
    return stripPre(version).satisfies(rule);
  }

  public static inline function stripPre(version:Version):Version
  {
    return '${version.major}.${version.minor}.${version.patch}';
  }

  public static inline function anyPatch(version:Version):VersionRule
  {
    return '${version.major}.${version.minor}.*';
  }

  public static inline function anyMinor(version:Version):VersionRule
  {
    return '${version.major}.*.*';
  }

  public static inline function combineRulesAnd(ruleA:VersionRule, ruleB:VersionRule):VersionRule
  {
    return AndRule(ruleA, ruleB);
  }

  public static inline function combineRulesOr(ruleA:VersionRule, ruleB:VersionRule):VersionRule
  {
    return OrRule(ruleA, ruleB);
  }

  public static function combineMultipleRulesAnd(rules:Array<VersionRule>):VersionRule
  {
    if (rules == null || rules.length == 0) return DEFAULT_VERSION_RULE;
    if (rules.length == 1) return rules[0];

    return rules.slice(1).fold(function(a:VersionRule, b:VersionRule):VersionRule {
      return combineRulesAnd(a, b);
    }, rules[0]);
  }

  public static function combineMultipleRulesOr(rules:Array<VersionRule>):VersionRule
  {
    if (rules == null || rules.length == 0) return DEFAULT_VERSION_RULE;
    if (rules.length == 1) return rules[0];

    return rules.slice(1).fold(function(a:VersionRule, b:VersionRule):VersionRule {
      return combineRulesOr(a, b);
    }, rules[0]);
  }
}
