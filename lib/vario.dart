class Vario {

  Map<int, double> _varioValues = {};
  int _averageTimeUs = 30000;

  Vario(averageTimeMs):_averageTimeUs = averageTimeMs * 1000;

  void setNewValue(double varioValue) {
    _varioValues.addAll({DateTime.now().microsecondsSinceEpoch: varioValue});
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
