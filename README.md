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

If you like this project, you may also want to check out its sibling project:

- [TF2 Attribute Extended Support][attrsupport], a zero-configuration plugin that improves
interactions in the game's native attributes.

[am-prof]: https://forums.alliedmods.net/member.php?u=252787
[wiki]: https://github.com/nosoop/SM-TFCustomAttributeStarterPack/wiki/Custom-Attribute-List
[attrsupport]: https://github.com/nosoop/SM-TFAttributeSupport

### Microframeworks

Some attributes are libraries that can be hooked onto by other plugin developers to implement
their own behaviors.  These include:

- `custom lunchbox effect`:  Replaces lunchbox effects &mdash; Sandvich, Bonk!, etc.
- `custom buff type`:  Replaces rage effects &mdash; currently only tested on Soldier's banners
and Sniper's Heatmaker, but should work on other weapons that use the rage system

The API for those frameworks are provided in `scripting/include/` and examples are available in
`scripting/{buff_overrides,lunchbox_effects}`.

## Installation

These installation steps assume that you're a server operator and are familiar with how
SourceMod works.  I can't provide individualized support on configuration; if you're running
into issues, please look at the [Troubleshooting page][trouble] first.

1.  Install the required runtime dependencies.
2.  [Download the latest `package.zip`][releases] and unpack.  Do *not* click the green "Code"
button with the download-like icon.  If you intend to modify / build from source, refer to the
[Building](#Building) section below.
	- Github now builds the entire package on every commit by default, so the latest release
	should be up-to-date.
3.  Copy the resulting `gamedata/`, and `plugins/` folders into your TF2 server's
`addons/sourcemod/` folder.
4.  [Apply custom attributes][apply-custom] to your weapons.

The plugins of any attributes that aren't in use can be safely removed from the server; the
project is designed to let you choose what attributes are running (though it does make
development easier at the same time).

[Custom Weapons plugin]: https://forums.alliedmods.net/showthread.php?t=285258
[apply-custom]: https://github.com/nosoop/SM-TFCustAttr/wiki/Applying-Custom-Attributes
[releases]: https://github.com/nosoop/SM-TFCustomAttributeStarterPack/releases
[trouble]: https://github.com/nosoop/SM-TFCustomAttributeStarterPack/wiki/Troubleshooting

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

(If you'd like to use a similar build system for your project,
[the template project is available here][ninjatemplate].)

[ninjatemplate]: https://github.com/nosoop/NinjaBuild-SMPlugin

## Dependencies

This project uses a bunch of external tooling.  Not all plugins use every dependency.
To run the plugins from this project, you will need the compiled releases of the following:

- [TF2 Custom Attributes][custattr]:  the core plugin, keeps track of equipment and their
associated key / value "attribute" pairs
- [TF2Attributes (my fork)][tf2attributes]:  interoperation with game attributes
- [DHooks with detour support][dynhooks]:  engine-level hooks
- [Custom Status HUD][]:  unified HUD library for drawing text elements on-screen
- [TF2 Max Speed Detour][maxspeed-ext]:  allows plugins to transform player maximum speed
before application
- [TF2 OnTakeDamage hooks][otd-ext]:  hooks into damage functions, specifically adding support
for manipulating (mini-)crits
- [Source Scramble][]:  memory-level tweaking, for when DHooks isn't enough
- [TF2 Wearable Tools][]:  checks for wearables
- [TF2 Econ Data][]:  identifies loadout slots for weapons, among other things
- [TF2Utils][]:  wrappers around some game functions / memory accessors
- [TF2 DamageInfo Tools][]:  additional wrapper solely for radius damage, because bomb entities
just don't work exactly right for custom explosions.  Uses Source Scramble's `MemoryBlock`
handles for struct allocation.

The following is only used when building from source; if you're just running the plugins, you do
not need these:

- [stocksoup][]:  personal library for reusable SourceMod functions
- [smlib][]:  massive community-created function stock library

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
[TF2Utils]: https://github.com/nosoop/SM-TFUtils
[smlib]: https://github.com/bcserv/smlib
[TF2 DamageInfo Tools]: https://github.com/nosoop/SM-TFDamageInfo

## License

This project uses the MIT license.  Do note that once compiled, SourceMod plugins are still
bound to GPLv3, but you're welcome to use the code as reference in other projects under the more
permissive license.

The following is a non-exhaustive list of what you're allowed / required to do (that said, this
is not legal advice):

- You can modify / use any of the code provided under the MIT license.  You may use the code as
reference documentation for things like MetaMod:Source bindings under that license.
- If you provide a compiled SourceMod plugin to another person, you MUST include the source code
with your modifications per GPLv3+.  (This applies to all SourceMod code / plugins in general.)
- If you run a compiled SourceMod plugin on a server you own, modified or not, you are under no
further obligation to provide any source code to any end-users (that is, any players on the
server).
	- Attribution is nice, but not required if you're simply running the code.  I couldn't care
	less, really.  If you do feel like providing a URL for attribution of any custom attributes
	available here that you are using, linking to this repository is preferred.  If you need
	a name to credit, "nosoop" is acceptable.  (I do have a number of other aliases.)

The software is provided "as is", and there is no real guarantee of support.  While I will make
an effort to maintain the plugins in response to game updates out of goodwill, it is at my
discretion &mdash; I can't afford to do so in perpetuity.
