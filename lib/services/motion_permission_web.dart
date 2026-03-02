import 'dart:js_interop';

@JS('requestMotionPermission')
external JSPromise<JSBoolean> _requestMotionPermissionJs();

Future<bool> requestMotionPermission() async {
  try {
    return (await _requestMotionPermissionJs().toDart).toDart;
  } catch (_) {
    return true;
  }
}
