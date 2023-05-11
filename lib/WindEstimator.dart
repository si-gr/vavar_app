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
  int _averageTimeUs = 30000;
  int _msBetweenWindEstimates = 20;

  WindEstimator(this._averageTimeUs, this._filterCovariance)
      : _windKalman = KalmanFilter(1, 1, _filterCovariance, _filterCovariance);

  void setFilterCovariance(double covariance) {
    _filterCovariance = covariance;
    _windKalman = KalmanFilter(1, 1, _filterCovariance, _filterCovariance);
  }

  void setMsBetweenWindEstimates(int ms) {
    _msBetweenWindEstimates = ms;
  }

  void addWindToAverage(windEstimate) {
    _windEstimates
        .addAll({DateTime.now().microsecondsSinceEpoch: windEstimate});
    _windEstimates.removeWhere((key, value) =>
        key < DateTime.now().microsecondsSinceEpoch - _averageTimeUs);
  }

  void setAveragingTime(int timeMs) {
    _averageTimeUs = timeMs;
  }

  Vector2 getKalmanWind() {
    return _windKalman.x_.xy;
  }

  Vector2 getAverageValue() {
    _windEstimates.removeWhere((key, value) =>
        key < DateTime.now().microsecondsSinceEpoch - _averageTimeUs);
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
      lastWindEstimateTime = DateTime.now().microsecondsSinceEpoch;
      return;
    }
    // lastairspeedvec - currentAirspeedvec = perceivedDifference
    // lastGroundSpeed - groundSpeed = realDifference
    // perceivedDifference - realDifference = wind
    int now = DateTime.now().microsecondsSinceEpoch;
    Vector2 groundSpeedChange = lastgroundSpeed - groundspeedVector;
    Vector2 currentAirspeed = Vector2(cos(yaw) * airspeed, sin(yaw) * airspeed);
    Vector2 airspeedChange = lastAirspeed - currentAirspeed;
    lastAirspeed = currentAirspeed;
    lastgroundSpeed = groundspeedVector;
    lastWindEstimate = airspeedChange - groundSpeedChange;
    _windKalman.Update(lastWindEstimate, now, true);
    lastWindEstimate =
        lastWindEstimate * (now - lastWindEstimateTime).toDouble() / 1000;
    lastWindEstimateTime = now;
  }
}
