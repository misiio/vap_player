# vap_player_platform_interface

A common platform interface for the [`flutter_vap_player`][1] plugin.

This interface allows platform-specific implementations of the `flutter_vap_player`
plugin, as well as the plugin itself, to ensure they are supporting the
same interface.

# Usage

To implement a new platform-specific implementation of `flutter_vap_player`, extend
[`VapPlayerPlatform`][2] with an implementation that performs the
platform-specific behavior, and when you register your plugin, set the default
`VapPlayerPlatform` by calling
`VapPlayerPlatform.instance = MyVapPlayerPlatform()`.

# Note on breaking changes

Strongly prefer non-breaking changes (such as adding a method to the interface)
over breaking changes for this package.

See https://flutter.dev/go/platform-interface-breaking-changes for a discussion
on why a less-clean interface is preferable to a breaking change.

[1]: ../vap_player
[2]: lib/vap_player_platform_interface.dart