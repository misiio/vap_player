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

  test('VAPX resource slot sizes take part in equality', () {
    const VapResource unsized = VapResource(
      id: '0',
      type: VapResourceType.image,
      tag: 'user_name',
    );

    final VapResource sized = unsized.withSize(width: 177, height: 35);

    expect(sized.id, '0');
    expect(sized.type, VapResourceType.image);
    expect(sized.tag, 'user_name');
    expect(sized.width, 177);
    expect(sized.height, 35);
    expect(sized, isNot(unsized));
    expect(sized, unsized.withSize(width: 177, height: 35));
  });
}

class _TestVapPlayerPlatform extends VapPlayerPlatform {}
