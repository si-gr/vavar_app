import 'dart:math';

import 'package:ble_larus_android/kalman2d.dart';
import 'package:vector_math/vector_math.dart';

/// Estimates short term wind changes based on yaw changes, airspeed changes and groundspeed changes

class WindEstimator {
  int lastWindEstimateTime = 0;
  Vector2 lastWindEstimate = Vector2(0, 0);
  Vector2 lastgroundSpeed = Vector2(0, 0);
  Vector2 lastAirspeed = Vector2(0, 0);
  KalmanFilter _windKalman = KalmanFilter(1, 1, 0.2, 0.2);
  double _filterCovariance = 0.2;
  Map<int, Vector2> _windEstimates = {};
  int _averageTimeMs = 30000;

  WindEstimator(this._averageTimeMs, this._filterCovariance):_windKalman = KalmanFilter(1, 1, _filterCovariance, _filterCovariance);

  void setFilterCovariance(double covariance) {
    _filterCovariance = covariance;
    _windKalman = KalmanFilter(1, 1, _filterCovariance, _filterCovariance);
  }

  void addWindToAverage(windEstimate) {
    _windEstimates
        .addAll({DateTime.now().millisecondsSinceEpoch: windEstimate});
    _windEstimates.removeWhere((key, value) =>
        key < DateTime.now().millisecondsSinceEpoch - _averageTimeMs);
  }

  void setAveragingTime(int timeMs) {
    _averageTimeMs = timeMs;
  }

  Vector2 getAverageValue() {
    _windEstimates.removeWhere((key, value) =>
        key < DateTime.now().millisecondsSinceEpoch - _averageTimeMs);
    if (_windEstimates.isNotEmpty) {
      Vector2 sum = Vector2(0, 0);
      _windEstimates.forEach((key, value) {
        sum += value;
      });
      return sum / _windEstimates.length.toDouble();
    } else {
      return Vector2(0, 0);
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
