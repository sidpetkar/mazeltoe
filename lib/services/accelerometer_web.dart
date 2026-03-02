import 'dart:async';
import 'dart:js_interop';

class AccelerometerEvent {
  final double x;
  final double y;
  final double z;
  AccelerometerEvent(this.x, this.y, this.z);
}

@JS('startMotionListener')
external void _startMotionListener();

@JS('getMotionX')
external JSNumber _getMotionX();

@JS('getMotionY')
external JSNumber _getMotionY();

@JS('getMotionZ')
external JSNumber _getMotionZ();

Stream<AccelerometerEvent> accelerometerEventStream() {
  _startMotionListener();
  return Stream.periodic(const Duration(milliseconds: 16), (_) {
    return AccelerometerEvent(
      _getMotionX().toDartDouble,
      _getMotionY().toDartDouble,
      _getMotionZ().toDartDouble,
    );
  });
}
