import 'dart:math';

import 'package:vector_math/vector_math.dart';

/// Estimates short term wind changes based on yaw changes, airspeed changes and groundspeed changes

class WindEstimator {
  int lastWindEstimateTime = 0;
  double lastYaw = 0;
  double lastAirspeed = 0;
  double yawChange = 0;
  double groundSpeedAngleChange = 0;
  Vector2 lastWindEstimate = Vector2(0, 0);
  Vector2 lastgroundSpeed = Vector2(0, 0);

  Map<int, Vector2> _windEstimates = {};
  int _averageTimeMs = 30000;

  WindEstimator(this._averageTimeMs);

  void addWindToAverage(windEstimate) {
    _windEstimates
        .addAll({DateTime.now().millisecondsSinceEpoch: windEstimate});
    _windEstimates.removeWhere((key, value) =>
        key < DateTime.now().millisecondsSinceEpoch - _averageTimeMs);
  }

  void setAveragingTime(int timeMs) {
    _averageTimeMs = timeMs;
  }

  double getAverageValue() {
    _windEstimates.removeWhere((key, value) =>
        key < DateTime.now().millisecondsSinceEpoch - _averageTimeMs);
    if (_windEstimates.length > 0) {
      double sum = 0;
      _windEstimates.forEach((key, value) {
        sum += sqrt(value.dot(value));
      });
      return sum / _windEstimates.length;
    } else {
      return 0;
    }
  }

  void estimateWind(double yaw, double airspeed, Vector2 groundspeedVector) {
    if (lastYaw == 0 && lastAirspeed == 0) {
      lastYaw = yaw;
      lastAirspeed = airspeed;
      lastgroundSpeed = groundspeedVector;
      lastWindEstimateTime = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    // yaw * airspeed - lastYaw * lastAirspeed = perceivedDifference
    // lastGroundSpeed - groundSpeed = realDifference
    // perceivedDifference - realDifference = wind
    double groundSpeedAngleChange =
        lastgroundSpeed.angleToSigned(groundspeedVector);
    double groundSpeedDifference = sqrt(lastgroundSpeed.dot(lastgroundSpeed)) -
        sqrt(groundspeedVector.dot(groundspeedVector));
    Vector2 groundVectorChange = Vector2(
        groundSpeedDifference * sin(groundSpeedAngleChange),
        groundSpeedDifference * cos(groundSpeedAngleChange));
    double airspeedChange = lastAirspeed - airspeed;
    yawChange = lastYaw - yaw;
    yawChange = (yawChange + pi) % (2 * pi) - pi;
    Vector2 perceivedVectorChange = Vector2(
        airspeedChange * sin(yawChange), airspeedChange * cos(yawChange));
    lastWindEstimate = perceivedVectorChange - groundVectorChange;
    int now = DateTime.now().millisecondsSinceEpoch;
    lastWindEstimate =
        lastWindEstimate * (now - lastWindEstimateTime).toDouble() / 1000;
    lastWindEstimateTime = DateTime.now().millisecondsSinceEpoch;
  }
}
