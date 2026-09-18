package ;

import haxe.format.JsonPrinter;
import haxe.format.JsonParser;
import haxe.Json;
import sys.io.File;
import haxe.io.Path;
import sys.FileSystem;

typedef HMMDependency =
{
  name:String,
  type:String,
  ?version: String,
  ?path:String,
  ?dir:String,
  ?url:String,
  ?ref:String,
}

/**
 * A simple tool to build a `hmm.json` file for the samples directory,
 * by scanning for `hmm.json` files in each sample subdirectory and merging
 * their dependencies into a single `hmm.json` file.
 */
class SamplesHMMBuilder
{
  /**
   * A list of sample directories to ignore when scanning for `hmm.json` files.
   * This is useful if certain samples do not work well with the system.
   */
  static final IGNORE_LIST:Array<String> = [];

  public static function main()
  {
    var scriptsPath:String = Path.directory(Sys.programPath());
    var workPath:String = Path.normalize('$scriptsPath/..');

    var searchPaths:Array<String> = FileSystem.readDirectory(workPath);
    var dependencies:Map<String, HMMDependency> = [];

    for (path in searchPaths)
    {
      if (IGNORE_LIST.contains(path)) continue;
      if (!FileSystem.isDirectory(path)) continue;

      var hmmPath:String = Path.join([path, 'hmm.json']);
      if (!FileSystem.exists(hmmPath)) continue;

      var hmmContent:String = File.getContent(hmmPath);
      try
      {
        var json:{ dependencies:Array<HMMDependency> } = Json.parse(hmmContent);
        if (json.dependencies == null) continue;

        for (dependency in json.dependencies)
        {
          if (dependencies.exists(dependency.name))
          {
            continue;
          }

          dependencies.set(dependency.name, dependency);
        }
      }
      catch (_) {}
    }

    var result = { dependencies: [] };
    for (dependency in dependencies)
    {
      if (dependency.name == 'polymod' && dependency.type == 'dev')
      {
        // Force correct relative path
        dependency.path = '..';
      }

      result.dependencies.push(dependency);
    }

    File.saveContent(Path.join([workPath, 'hmm.json']), Json.stringify(result, '  '));
  }
}
