import 'package:vector_math/vector_math_64.dart';
import 'dart:math';

class KalmanFilter {
  Vector4 x_; // state vector
  Matrix4 F_; // state transition matrix
  Matrix4 Q_; // process covariance matrix
  Matrix4 P_; // covariance matrix
  Matrix4 H_; // measurement matrix
  Matrix2 R_; // measurement covariance matrix
  Matrix4 I_; // identity matrix
  double noise_ax_;
  double noise_ay_;
  int previous_ts_ = 0;
  bool initialized_ = false;

  /// Create a Kalman filter with the specified noise parameters. Covariance is the responsiveness of the filter to changes in the state. The higher the covariance, the more responsive the filter is to changes in the state. The lower the covariance, the smoother the filter is. The covariance is measured in meters^2. The noise parameters are the standard deviation of the noise in the x and y directions. The noise parameters are measured in meters/second^2.
  KalmanFilter(double noise_ax, double noise_ay, double z_cov_x, double z_cov_y)
      : F_ = Matrix4.identity(),
        x_ = Vector4(0, 0, 0, 0),
        I_ = Matrix4.identity(),
        P_ = Matrix4.identity(),
        Q_ = Matrix4.zero(),
        H_ = Matrix4.zero(),
        R_ = Matrix2.zero(),
        noise_ax_ = noise_ax,
        noise_ay_ = noise_ay {
    // H_(2, 4),
    // initialize covariance matrix P we are more confident about location than
    // velocity.
    P_.setEntry(2, 2, 1000);
    P_.setEntry(3, 3, 1000);

    // measurement covariance
    R_.setColumns(Vector2(z_cov_x, 0), Vector2(0, z_cov_y));

    // measurement matrix Z_pred = H*X
    H_.setEntry(0, 0, 1);
    H_.setEntry(2, 1, 1);
    //H_ << 1, 0, 0, 0, 0, 1, 0, 0;
  }

  void Predict_() {
    x_ = F_ * x_;
    P_ = F_ * P_ * F_.transposed() + Q_;
  }

  void Update(Vector2 z, int timestamp, bool bearing) {
    if (!initialized_) {
      x_ = Vector4(z[0], z[1], 0, 0);
      initialized_ = true;
      previous_ts_ = timestamp;
      return;
    }
    double dt = (timestamp.toDouble() - previous_ts_.toDouble());
    dt = dt / 1000000;
    // Update F
    F_.setEntry(0, 2, dt);
    F_.setEntry(1, 3, dt);
    // Update Q
    double dt2 = pow(dt, 2).toDouble();
    double dt3 = pow(dt, 3).toDouble();
    double dt4 = pow(dt, 4).toDouble();
    //Q_ << (noise_ax_ / 4) * dt4, 0, (noise_ax_ / 2) * dt3, 0, 0, (noise_ay_ / 4) * dt4, 0,
    //    (noise_ay_ / 2) * dt3, (noise_ax_ / 2) * dt3, 0, noise_ax_ * dt2, 0, 0, noise_ay_ * dt3 / 2,
    //    0, noise_ay_ * dt2;
    Q_ = Matrix4(
        (noise_ax_ / 4) * dt4,
        0,
        (noise_ax_ / 2) * dt3,
        0,
        0,
        (noise_ay_ / 4) * dt4,
        0,
        (noise_ay_ / 2) * dt3,
        (noise_ax_ / 2) * dt3,
        0,
        noise_ax_ * dt2,
        0,
        0,
        noise_ay_ * dt3 / 2,
        0,
        noise_ay_ * dt2);
    Predict_();
    // Update using the new measurements
    Vector2 z_pred = Vector2(2, 1);
    if (bearing) {
      //double c1 = pow(x_.x(0) * x_(0) + x_(1) * x_(1);
      //double c2 = sqrt(c1);
      double c1 = x_.length2;
      double c2 = x_.length;
      if (c2 > 0.0001) {
        //H_ << x_(0) / c2, x_(1) / c2, 0, 0, -x_(1) / c1, x_(0) / c1, 0, 0;  // Jacobian Matrix
        H_ = Matrix4(x_.x / c2, x_.y / c2, 0, 0, -x_.y / c1, x_.x / c1, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0);
        //z_pred << c2, std::atan2(x_(1), x_(0));  // h(x)-> (sqrt(x^2+y^2), atan(y,x))
        z_pred = Vector2(c2, atan2(x_.y, x_.x));
      } else {
        z_pred = Vector2(
            H_.getRow(0).dot(x_),
            H_
                .getRow(1)
                .dot(x_)); // 2x4 * 4x1 = 2x1, in this case last 2 rows are 0
      }
      Vector2 y = z - z_pred;
      Matrix4 S4 = H_ * P_ * H_.transposed();
      Matrix2 S =
          getUpper22(S4) + R_; // 2x4 * 4x4 * 4x2 + 2x2 = 2x2 in our case
      Matrix4 K4 = P_ * H_.transposed();
      Matrix2 K = getUpper22(K4) * S.invert();
      x_ = x_ + (K * y);
      P_ = (I_ - K * H_) * P_;
      previous_ts_ = timestamp;
    }
  }

  Matrix2 getUpper22(Matrix4 m4) {
    return Matrix2(
        m4.entry(0, 0), m4.entry(0, 1), m4.entry(1, 0), m4.entry(1, 1));
  }
}
