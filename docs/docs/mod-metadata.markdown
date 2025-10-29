---
title: Mod Metadata
---
{% include toc.html %}

# Mod Metadata

In order to be recognized by Polymod, a mod folder must contain a metadata file. By default, this file is located at `_polymod_meta.json`, but this can be reconfigured in your own projects. See [Configuring Polymod](./../configuring-polymod) for more information.

A mod's metadata contains all the information needed for your project to not only recognize a mod and validate its compatibility, but also display it to your users. It includes a title, description, author, and even optionally an icon you can display.

## Scanning for Mods

In your application, you can retrieve the metadata for all installed mods using the following function:

```haxe
/**
 * Scan the modRoot directory for available mods and returns all their respective metadata entries.
 * @param modRoot The root directory to scan for mods in.
 * @param apiVersionStr (optional) Enforce a specific API version on mods.
 * @param errorCallback (optional) A function to receive any PolymodErrors that occur.
 * @return A list of ModMetadata objects, or an empty list.
 */
Polymod.scan(modRoot, apiVersionStr, errorCallback);
```

## _polymod_meta.json

The metadata JSON contains data which is loaded when scanning mods, and is meant to provide readable information about the mod to users.

```json
{
	"title":"Dragon",
	"description":"Replaces Bees with Dragons",
	"homepage": "https://example.com/dragons",
	"contributors": [
		{
			"name": "Lars A. Doucet",
			"role": "Developer"
		}
	],
	"api_version":"0.1.0",
	"mod_version":"1.0.0-alpha",
	"license":"CC BY 4.0,MIT"
}
```

- `title`: The human-readable name of the mod.
- `description`: A readable description of the mod. Keep this to only a couple sentences so it can be read without scrolling.
- `homepage`: A URL linking to the homepage for the mod. This should be a link where the mod is available for download if the user wants to check for updates.
- `contributors`: A list of objects, representing each of the contributors to the mod, with their `name`, `role`, and optionally an `email` or `url`.
- `author`: A string containing the name of the mod's author.
    - **This field is deprecated**, please use the `contributors` field instead.
    - This field is backwards compatible; requesting the `author` retrieves the name of the first contributor if available, and falls back to the `author` otherwise.
- `api_version`: This defines the API version for your app which the mod was designed to use.
    - If the major, minor, AND patch version do not match, the mod will not load. This behavior can be configured; see [Configuring Polymod](./../configuring-polymod/).
    - This version must adhere to the Semantic Versioning 2.0 format.
- `mod_version`: This represents the version for the mod itself, and does not relate to the API version.
    - Mod creators should adhere to the Semantic Versioning 2.0 format.
- `license`: The licensing terms for your mod. Put a comma between each of the licenses your mod uses.
    - Please define these, it's important!
    - A mod may have multiple licenses, since scripts and code can differ in licensing from art or text.
    - Polymod recommends the [MIT License](https://opensource.org/licenses/MIT) for code and the [Creative Commons](https://creativecommons.org/) for assets.

## Other files

It is highly recommended that you also include the following files:

- `_polymod_icon.png`: If a mod provides this image file, it will be read into memory and provided as a Bytes in the `ModMetadata` object.
- `LICENSE.txt`: This should contain general licensing terms
- `ASSET_LICENSE.txt`: This should contain asset-specific licensing terms. Creative Commons is recommended.
- `CODE_LICENSE.txt`: This should contain code/script-specific licensing terms, MIT is recommended.
