package polymod.util;

import polymod.Polymod;
import thx.semver.VersionRule;

/**
 * Utilities for managing dependencies.
 * Provides two key functions:
 * - Ensure a mod is not loaded if a dependency is missing or has a mismatched version.
 * - Ensure mods are loaded in the correct order (dependency mods before dependent mods).
 */
@:nullSafety
class DependencyUtil
{
  /**
   * Given an ordered list of mods, return a reordered list of mods which satisfies dependency order.
   *
   * @param mods The list of mods to reorder.
   * @param skipErrors If true, omit mods which cannot be reordered or whose dependencies are not met.
   *                     If false, raise an error in these cases and return `[]`.
   * @return The reordered list of mods, or `[]` if an error occurred.
   */
  public static function sortByDependencies(modList:Array<ModMetadata>, skipErrors:Bool = false):Array<ModMetadata>
  {
    if (skipErrors)
    {
      // If skipErrors is true, a mod with unmet dependencies will call Polymod.warn() and be omitted from the list.
      var filteredMods = filterDependencies(modList);

      return buildTopologyForDependencies(filteredMods, true);
    }
    else
    {
      // If skipErrors is false, a mod with unmet dependencies will call Polymod.error() and return null.
      if (!validateDependencies(modList))
      {
        return [];
      }

      return buildTopologyForDependencies(modList, false);
    }
  }

  /**
   * Given an unordered list of mods, return a list of only the mods whose dependencies are met.
   */
  static function filterDependencies(modList:Array<ModMetadata>):Array<ModMetadata>
  {
    var result:Array<ModMetadata> = [];

    for (currentMod in modList) {
      var currentModMissingDep:Bool = false;
      for (depId => depVersionRule in currentMod.dependencies) {
        // Check that the dependency is loaded.
        // NOTE: We don't care about the dependency being loaded before this mod,
        // we'll reorder the mods later.

        var depMod:Null<ModMetadata> = null;
        for (mod in modList) {
          if (mod.id == depId) depMod = mod;
        }

        if (depMod == null) {
          Polymod.warning(MOD_DEPENDENCY_UNMET, 'Skipping mod "${currentMod.id}", required dependency "${depId}" not found.', INIT);
          currentModMissingDep = true;
          break;
        } else {
          if (VersionUtil.match(depMod.modVersion, depVersionRule)) {
            // The dependency is met!
            continue;
          } else {
            Polymod.warning(MOD_DEPENDENCY_UNMET, 'Skipping mod "${currentMod.id}", required dependency "${depId}" has version "${depMod.modVersion}" but we need "${depVersionRule}".', INIT);
          }
        }
      }

      if (!currentModMissingDep) result.push(currentMod);
    }

    return result;
  }

  /**
   * Given an unordered list of mods, return true only if all dependencies are met.
   *
   * @param modList The list of mods to validate.
   * @return `true` if all dependencies are met, `false` otherwise.
   */
  public static function validateDependencies(modList:Array<ModMetadata>):Bool
  {
    // Compile a map of mod dependencies.
    var deps:ModDependencies = compileDependencies(modList);

    // List just the mods that are a dependency to another mod.
    var relevantMods:Array<ModMetadata> = modList.filter((mod) -> deps.exists(mod.id));

    // Check that all dependencies are satisfied.
    for (depModId => depRule in deps)
    {
      // Check that the dependency is in the current list.
      var depMod:Null<ModMetadata> = null;
      for (mod in relevantMods)
      {
        if (mod.id == depModId)
        {
          depMod = mod;
          break;
        }
      }

      // If the dependency is not found, throw a warning/error.
      if (depMod == null)
      {
        Polymod.error(MOD_DEPENDENCY_UNMET, 'Dependency "${depModId}" not found.', INIT);
        return false;
      } else if (VersionUtil.match(depMod.modVersion, depRule))
      {
        // If the dependency is found, validate the version rule.
        continue;
      }
      else
      {
        Polymod.error(MOD_DEPENDENCY_VERSION_MISMATCH, 'Dependency "${depModId}" has version "${depMod.modVersion}" but requires "${depRule}".', INIT);
        return false;
      }
    }

    // All dependencies validated.
    return true;
  }

  /**
   * Based on the ordered modlist, create a reordered modlist based on each mod's dependencies.
   * Mods will be sorted first in dependency order, then further sorted based on the order of the modlist.
   *
   * @param modList The list of mods to reorder.
   */
  static function buildTopologyForDependencies(modList:Array<ModMetadata>, skipErrors = false):Array<ModMetadata>
  {
    trace('Building topology for mods: ${modList}');

    // Build a map of dependencies.
    var dependencies:Map<String, Array<String>> = [];

    // Add the mod ID as a key, then add the mod ID as a value to each dependency.
    // The result is that mods with no dependencies will have an empty array as a value,
    // and mods with dependencies will have an array of the dependency mod IDs.
    for (mod in modList)
    {
      if (!dependencies.exists(mod.id)) dependencies.set(mod.id, []);

      var deps = mod.dependencies;
      if (deps != null)
      {
        for (depKey in deps.keys())
        {
          var depList:Null<Array<String>> = dependencies.get(mod.id);
          if (depList != null)
          {
            depList.push(depKey);
          }
          else
          {
            dependencies.set(mod.id, [depKey]);
          }
        }
      }
    }

    // Add the optional dependencies to the dependencies map.
    for (mod in modList)
    {
      // We consider optional dependencies when building topologies,
      // but we don't consider them when validating dependencies.
      var optDeps = mod.optionalDependencies;
      if (optDeps != null)
      {
        for (depKey in optDeps.keys())
        {
          if (dependencies.exists(depKey))
          {
            // Ensure the dependency is loaded before this mod.
            var depList = dependencies.get(mod.id);
            if (depList != null) {
              depList.push(depKey);
            } else {
              dependencies.set(mod.id, [depKey]);
            }
          }
          else
          {
            Polymod.info(MOD_OPTIONAL_DEPENDENCY_UNMET, 'Optional dependency "${depKey}" for mod "${mod.id}" not enabled, skipping.', INIT);
          }
        }
      }
    }

    return buildTopology_Recursive(modList, dependencies, skipErrors) ?? [];
  }

  static function buildTopology_Recursive(modList:Array<ModMetadata>, dependencies:Map<String, Array<String>>, skipErrors:Bool = false):Null<Array<ModMetadata>>
  {
    if (modList.length == 0) return [];

    var result:Array<ModMetadata> = [];

    // Loop through the dependencies, finding the mod IDs with no dependencies.
    var rootLevelMods:Array<String> = [];
    for (mod in modList)
    {
      var deps:Array<String> = dependencies.get(mod.id) ?? [];
      if (deps.length == 0)
      {
        rootLevelMods.push(mod.id);
      }
    }

    // If the root level mod list is empty, then there is a circular dependency.
    if (rootLevelMods.length == 0)
    {
      var modList = modList.map(function(mod) {
        return mod.id;
      }).join(', ');
      if (skipErrors)
      {
        Polymod.warning(MOD_DEPENDENCY_CYCLICAL, 'Circular dependency detected between mods: ${modList}', INIT);
        return [];
      }
      else
      {
        Polymod.error(MOD_DEPENDENCY_CYCLICAL, 'Circular dependency detected between mods: ${modList}', INIT);
        return null;
      }
    }

    var childLevelMods:Array<ModMetadata> = [];

    for (modData in modList)
    {
      if (rootLevelMods.indexOf(modData.id) != -1)
      {
        // Add the mod to the result list.
        result.push(modData);

        // Remove the mod from the dependency list.
        dependencies.remove(modData.id);

        // Remove the mod from each dependency list.
        for (depKey => depList in dependencies)
        {
          var index = depList.indexOf(modData.id);
          // If the mod is in the dependency list, remove it.
          if (index != -1)
          {
            depList.splice(index, 1);
          }
        }
      }
      else
      {
        childLevelMods.push(modData);
      }
    }

    // result now contains the mods with no dependencies, in the order they appear in the mod list.
    // dependencies now contains the remaining dependencies, with the root level mods removed.
    var innerResult = buildTopology_Recursive(childLevelMods, dependencies, skipErrors);

    // Pass circular dependency issues upward.
    if (innerResult == null) return null;

    return result.concat(innerResult);
  }

  /**
   * Given a list of mods with required dependencies, return a merged list of mod dependency versions.
   *
   * For example, if one mod requires `>1.2.0` of `modA` and another requires `>1.3.0` of `modA`,
   * the merged list will be `[modA: '>1.2.0 && >1.3.0']`.
   *
   * @param modList The list of mods to compile dependencies for.
   * @return A map of mod IDs to versions.
   */
  public static function compileDependencies(modList:Array<ModMetadata>):Map<String, VersionRule>
  {
    var result:Map<String, VersionRule> = [];

    for (mod in modList)
    {
      if (result[mod.id] == null) result[mod.id] = VersionUtil.DEFAULT_VERSION_RULE;

      if (mod.dependencies != null)
      {
        for (dependencyId => dependencyRule in mod.dependencies)
        {
          var currentDependency = result[dependencyId];
          if (currentDependency != null)
          {
            var compositeDependency:VersionRule = VersionUtil.combineRulesAnd(currentDependency, dependencyRule);
            result[dependencyId] = compositeDependency;
          }
          else
          {
            result[dependencyId] = dependencyRule;
          }
        }
      }
    }

    return result;
  }
}
