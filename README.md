# TF2 Custom Attribute Starter Pack

A collection of (mostly) production-ready custom attributes written for
[the Custom Attribute framework][custattr].

I'll move the other ones eventually&hellip;

[custattr]: https://github.com/nosoop/SM-TFCustAttr

## About

This repository contains attributes I've written.  I don't run a Custom Weapon server, so most
of the plugins are made through work-for-hire.  If you'd like a custom attribute created, feel
free to [contact me on AlliedModders][am-prof] &mdash; I'm open to inquiries.

The [wiki][] documents the available custom attributes.

Special thanks to Karma Charger for allowing the release of the stuff I've written for him;
a lot of the plugins available here were created for his videos.

[am-prof]: https://forums.alliedmods.net/member.php?u=252787
[wiki]: https://github.com/nosoop/SM-TFCustomAttributeStarterPack/wiki/Custom-Attribute-List

### Microframeworks

Some attributes are libraries that can be hooked onto by other plugin developers to implement
their own behaviors.  These include:

- `custom lunchbox effect`:  Replaces lunchbox effects &mdash; Sandvich, Bonk!, etc.
- `custom buff type`:  Replaces rage effects &mdash; currently only tested on Soldier's banners
and Sniper's Heatmaker, but should work on other weapons that use the rage system

The API for those frameworks are provided in `scripting/include/` and examples are available in
the subfolders of `scripting/`.

## Installation

These installation steps assume that you're a server operator and are familiar with how
SourceMod works.

1.  Install the required runtime dependencies.
2.  [Download the latest `package.zip`][releases] (possibly stale) and unpack, or manually build
the latest commit.
3.  Copy the resulting `gamedata/`, and `plugins/` folders into your TF2 server's
`addons/sourcemod/` folder.
4.  [Apply custom attributes][apply-custom] to your weapons.

The plugins of any attributes that aren't in use can be safely removed from the server; the
project is designed to let you choose what attributes are running (though it does make
development easier at the same time).

[Custom Weapons plugin]: https://forums.alliedmods.net/showthread.php?t=285258
[apply-custom]: https://github.com/nosoop/SM-TFCustAttr/wiki/Applying-Custom-Attributes
[releases]: https://github.com/nosoop/SM-TFCustomAttributeStarterPack/releases

### Custom Weapon Configs

The included CW3 configuration files are provided as-is for attribute demonstration purposes and
not intended to showcase completely balanced weapons.

### Building

This project can be built in a reproductive manner with [Ninja](https://ninja-build.org/),
`git`, and Python 3.

1.  Clone the repository and its submodules: `git clone --recurse-submodules ...`
2.  Execute `python3 configure.py --spcomp-dir ${PATH}` within the repo, where `${PATH}` is the
path to the directory containing `spcomp`.  Verified working against 1.9 and 1.10.
3.  Run `ninja`.  Output will be available under `build/`.

## Dependencies

This project uses a bunch of external tooling.  Not all plugins use every dependency.
To run the plugins from this project, you will need the compiled releases of the following:

- [TF2Attributes (my fork)][tf2attributes]:  interoperation with game attributes
- [DHooks with detour support][dynhooks]:  engine-level hooks
- [Custom Status HUD][]:  unified HUD library for drawing text elements on-screen
- [TF2 Max Speed Detour][maxspeed-ext]:  allows plugins to transform player maximum speed
before application
- [TF2 OnTakeDamage hooks][otd-ext]:  hooks into damage functions, specifically adding support
for manipulating (mini-)crits
- [Source Scramble][]:  memory-level tweaking, for when DHooks isn't enough
- [TF2 Wearable Tools][]:  checks for wearables
- [TF2 Econ Data][]: identifies loadout slots for weapons, among other things

The following is only used when building from source; if you're just running the plugins, you do
not need these:

- [stocksoup][]:  personal library for reusable SourceMod functions

Includes are bundled in the `third_party/` subdirectory to ensure builds are consistent.

[tf2attributes]: https://github.com/nosoop/tf2attributes
[dynhooks]: https://forums.alliedmods.net/showpost.php?p=2588686&postcount=589
[stocksoup]: https://github.com/nosoop/stocksoup
[Custom Status HUD]: https://github.com/nosoop/SM-CustomStatusHUD
[maxspeed-ext]: https://github.com/nosoop/SMExt-TFMaxSpeedDetour
[otd-ext]: https://github.com/nosoop/SM-TFOnTakeDamage
[Source Scramble]: https://github.com/nosoop/SMExt-SourceScramble
[TF2 Wearable Tools]: https://github.com/nosoop/sourcemod-tf2wearables
[TF2 Econ Data]: https://github.com/nosoop/SM-TFEconData

## License

This project uses the MIT license.  Do note that once compiled, SourceMod plugins are still
bound to GPLv3, but you're welcome to use the code as reference in other projects under the more
permissive license.

The software is provided "as is", and there is no real guarantee of support.
