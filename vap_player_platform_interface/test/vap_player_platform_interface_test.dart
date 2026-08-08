import 'package:flutter_test/flutter_test.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

void main() {
  final VapPlayerPlatform originalPlatform = VapPlayerPlatform.instance;

  tearDown(() {
    VapPlayerPlatform.instance = originalPlatform;
  });

  test('accepts implementations that extend VapPlayerPlatform', () {
    final _TestVapPlayerPlatform platform = _TestVapPlayerPlatform();

    VapPlayerPlatform.instance = platform;

    expect(VapPlayerPlatform.instance, same(platform));
  });

  test('default platform methods remain explicitly unimplemented', () {
    VapPlayerPlatform.instance = _TestVapPlayerPlatform();

    expect(
      () => VapPlayerPlatform.instance.create(const VapCreationOptions()),
      throwsUnimplementedError,
    );
  });

  test('VAPX resources have value equality', () {
    const VapResource first = VapResource(
      id: 'avatar',
      type: VapResourceType.image,
      tag: '[sImg1]',
    );
    const VapResource second = VapResource(
      id: 'avatar',
      type: VapResourceType.image,
      tag: '[sImg1]',
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}

class _TestVapPlayerPlatform extends VapPlayerPlatform {}
