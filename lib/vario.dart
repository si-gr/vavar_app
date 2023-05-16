import 'package:ble_larus_android/kalman1d.dart';

class Vario {

  Map<int, double> _varioValues = {};
  int _averageTimeUs = 30000;
  Kalman1D kalman1d = Kalman1D(500.0, 0.002);
  Kalman1D kalman1dAverage = Kalman1D(500.0, 0.0005);

  Vario(averageTimeMs):_averageTimeUs = averageTimeMs * 1000;

  void setKalmanQ(double q) {
    kalman1d.setGain(q);
  }

  void setKalmanAverageQ(double q) {
    kalman1dAverage.setGain(q);
  }

  void setNewValue(double varioValue) {
    if (_varioValues.isEmpty){
      kalman1d.setLastEstimate(varioValue);
      kalman1dAverage.setLastEstimate(varioValue);
    } else {
      kalman1d.setNewValue(varioValue);
      kalman1dAverage.setNewValue(varioValue);
    }
    _varioValues.addAll({DateTime.now().microsecondsSinceEpoch: kalman1d.getLastValue()});
    _varioValues.removeWhere((key, value) =>
        key < DateTime.now().microsecondsSinceEpoch - _averageTimeUs);
  }

  double getCurrentValue() {
    if (_varioValues.length > 0) {
      return _varioValues[_varioValues.keys.last]!;
    } else {
      return 0;
    }
  }

  double getFilteredVario() {
    return kalman1d.getLastValue();
  }

  double getFilteredAverageVario() {
    return kalman1dAverage.getLastValue();
  }

  void setAveragingTime(int timeMs) {
    _averageTimeUs = timeMs * 1000;
  }

  double getAverageValue() {
    _varioValues.removeWhere((key, value) =>
        key < DateTime.now().microsecondsSinceEpoch - _averageTimeUs);
    if (_varioValues.length > 0) {
      double sum = 0;
      _varioValues.forEach((key, value) {
        sum += value;
      });
      return sum / _varioValues.length;
    } else {
      return 0;
    }
  }
}
