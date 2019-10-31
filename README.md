# TF2 Custom Attribute Starter Pack

A collection of (mostly) production-ready custom attributes written for
[the Custom Attribute framework][custattr].

I'll move the other ones eventually&hellip;

[custattr]: https://github.com/nosoop/SM-TFCustAttr

## About

This repository contains attributes I've written.  I don't run a Custom Weapon server, so most
of the plugins are made through work-for-hire.  If you'd like a custom attribute created, feel
free to [contact me on AlliedModders][privmsg].

The [wiki][] documents the available custom attributes.

Special thanks to Karma Charger for allowing the release of the stuff I've written for him;
a lot of the plugins available here were created for his videos.

[privmsg]: https://forums.alliedmods.net/private.php?do=newpm&u=252787
[wiki]: https://github.com/nosoop/SM-TFCustomAttributeStarterPack/wiki/Custom-Attribute-List

## Installation

It's assumed that you're a server operator and are familiar with how SourceMod works.  I can't
provide free personalized support in that regard, unfortunately &mdash; read up on how to set up
your own TF2 server.

As mentioned, this uses my own [Custom Attribute framework][custattr], so you'll want to follow
the instructions for [applying custom attributes][apply-custom].

(I still need to add vendored includes and a dependency list to make this fully compilable per
issue #9, so if you're not a programmer you'll have to wait a bit more for those; apologies.)

[Custom Weapons plugin]: https://forums.alliedmods.net/showthread.php?t=285258
[apply-custom]: https://github.com/nosoop/SM-TFCustAttr/wiki/Applying-Custom-Attributes

## Dependencies

This project uses a bunch of external tooling.  Not all plugins use every dependency.

- TF2Attributes (my fork):  interoperation with game attributes
- DHooks with detour support:  engine-level hooks
- stocksoup:  personal library for reusable SourceMod functions
- Custom Status HUD:  unified HUD library for drawing text elements on-screen
- TF2 Max Speed Detour:  allows plugins to transform player maximum speed before application
- TF2 OnTakeDamage hooks:  hooks into damage functions, specifically adding support for
manipulating (mini-)crits
- Source Scramble:  memory-level tweaking, for when DHooks isn't enough
- TF2 Wearable Tools:  checks for wearables
