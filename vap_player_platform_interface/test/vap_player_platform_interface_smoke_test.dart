import 'package:flutter_test/flutter_test.dart';
import 'package:vap_player_platform_interface/vap_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default platform instance is available', () {
    expect(VapPlayerPlatform.instance, isNotNull);
  });
}
