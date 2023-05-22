import 'package:vector_math/vector_math_64.dart';

class APWindStore{
  List<Vector3> windRollingWindow = [];
  Vector3 windAverage = Vector3(0, 0, 0);
  Vector3 currentWindChange = Vector3(0, 0, 0);
  int rollingWindowSize = 10;

  APWindStore({required this.rollingWindowSize});

  void update(Vector3 wind){
    windRollingWindow.add(wind);
    if(windRollingWindow.length > rollingWindowSize){
      windRollingWindow.removeAt(0);
    }
    for (var i = 0; i < windRollingWindow.length; i++) {
      windAverage += windRollingWindow[i];
    }
    windAverage /= windRollingWindow.length.toDouble();
    currentWindChange = windAverage - wind;
  }

}