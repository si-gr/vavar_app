class Vario {

  Map<int, double> _varioValues = {};
  int _averageTimeMs = 30000;

  Vario(this._averageTimeMs);

  void setNewValue(double varioValue) {
    _varioValues.addAll({DateTime.now().millisecondsSinceEpoch: varioValue});
    _varioValues.removeWhere((key, value) =>
        key < DateTime.now().millisecondsSinceEpoch - _averageTimeMs);
  }

  double getCurrentValue() {
    if (_varioValues.length > 0) {
      return _varioValues[_varioValues.keys.last]!;
    } else {
      return 0;
    }
  }

  void setAveragingTime(int timeMs) {
    _averageTimeMs = timeMs;
  }

  double getAverageValue() {
    _varioValues.removeWhere((key, value) =>
        key < DateTime.now().millisecondsSinceEpoch - _averageTimeMs);
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
