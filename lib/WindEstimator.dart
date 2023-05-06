import 'dart:math';

import 'package:vector_math/vector_math.dart';

/// Estimates short term wind changes based on yaw changes, airspeed changes and groundspeed changes

class WindEstimator {
  int lastWindEstimateTime = 0;
  Vector2 lastWindEstimate = Vector2(0, 0);
  Vector2 lastgroundSpeed = Vector2(0, 0);
  Vector2 lastAirspeed = Vector2(0, 0);

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
    if (lastAirspeed.x == 0) {
      lastAirspeed = Vector2(cos(yaw) * airspeed, sin(yaw) * airspeed);
      lastgroundSpeed = groundspeedVector;
      lastWindEstimateTime = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    // lastairspeedvec - currentAirspeedvec = perceivedDifference
    // lastGroundSpeed - groundSpeed = realDifference
    // perceivedDifference - realDifference = wind
    Vector2 groundSpeedChange = lastgroundSpeed - groundspeedVector;
    Vector2 currentAirspeed = Vector2(cos(yaw) * airspeed, sin(yaw) * airspeed);
    Vector2 airspeedChange = lastAirspeed - currentAirspeed;
    lastAirspeed = currentAirspeed;
    lastgroundSpeed = groundspeedVector;
    lastWindEstimate = airspeedChange - groundSpeedChange;
    int now = DateTime.now().millisecondsSinceEpoch;
    lastWindEstimate =
        lastWindEstimate * (now - lastWindEstimateTime).toDouble() / 1000;
    lastWindEstimateTime = DateTime.now().millisecondsSinceEpoch;
  }
}
