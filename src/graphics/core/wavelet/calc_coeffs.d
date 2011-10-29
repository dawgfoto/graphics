module graphics.core.wavelet.calc_coeffs;

import guip.point;

enum Quad {
  _00, // top-left
  _01, // top-right
  _10, // bottom-left
  _11, // bottom-right
};


//==============================================================================

//------------------------------------------------------------------------------

struct Interim {
  double Kx, Ky, Lx, Ly;
};


//------------------------------------------------------------------------------

void updateCoeffs(size_t K, Quad Q)(uint scale, const ref FPoint[K] pts, ref float[3] coeffs) {
  auto tmp = calcInterim!K(1.0 / scale, pts);
  addInterim!Q(tmp, coeffs);
}


//------------------------------------------------------------------------------

Interim calcInterim(size_t K : 2)(double rscale, const ref FPoint[2] pts) {
  Interim tmp;
  tmp.Kx = (1.f / 4.f) * (pts[1].y - pts[0].y) * rscale;
  tmp.Ky = (1.f / 4.f) * (pts[0].x - pts[1].x) * rscale;

  tmp.Lx = (1.f / 2.f) * tmp.Kx * (pts[0].x + pts[1].x) * rscale;
  tmp.Ly = (1.f / 2.f) * tmp.Ky * (pts[0].y + pts[1].y) * rscale;

  return tmp;
}

Interim calcInterim(size_t K : 3)(double rscale, const ref FPoint[3] pts) {
  Interim tmp;
  tmp.Kx = (1.f / 4.f) * (pts[2].y - pts[0].y) * rscale;
  tmp.Ky = (1.f / 4.f) * (pts[0].x - pts[2].x) * rscale;

  const double Lcommon = (1.f / 24.f) * (
      2 * (determinant(pts[0], pts[1]) + determinant(pts[1], pts[2]))
      + determinant(pts[0], pts[2])
  ) * rscale * rscale;
  const double Ldiff = (3.f / 24.f) * (pts[2].x*pts[2].y - pts[0].x * pts[0].y)  * rscale * rscale;
  tmp.Lx = Lcommon + Ldiff;
  tmp.Ly = Lcommon - Ldiff;

  return tmp;
}

Interim calcInterim(size_t K : 4)(double rscale, const ref FPoint[4] pts) {
  Interim tmp;
  tmp.Kx = (1.f / 4.f) * (pts[3].y - pts[0].y) * rscale;
  tmp.Ky = (1.f / 4.f) * (pts[0].x - pts[3].x) * rscale;

  const double Lcommon = (1.f / 80.f) * (
      3 * (
          2 * (determinant(pts[2], pts[3]) + determinant(pts[0], pts[1]))
          + determinant(pts[1], pts[2])
          + determinant(pts[1], pts[3])
          + determinant(pts[0], pts[2])
      )
      + determinant(pts[0], pts[3])
  ) * rscale * rscale;
  const double Ldiff = (10.f / 80.f) * (pts[3].x * pts[3].y - pts[0].x * pts[0].y)  * rscale * rscale;
  tmp.Lx = Lcommon + Ldiff;
  tmp.Ly = Lcommon - Ldiff;

  return tmp;
}


//------------------------------------------------------------------------------

void addInterim(Quad Q : Quad._00)(in Interim tmp, ref float[3] coeffs) {
  coeffs[0] += tmp.Lx;
  coeffs[1] += tmp.Ly;
  coeffs[2] += tmp.Lx;
}

void addInterim(Quad Q : Quad._01)(in Interim tmp, ref float[3] coeffs) {
  coeffs[0] += tmp.Kx - tmp.Lx;
  coeffs[1] += tmp.Ly;
  coeffs[2] += tmp.Kx - tmp.Lx;
}

void addInterim(Quad Q : Quad._10)(in Interim tmp, ref float[3] coeffs) {
  coeffs[0] += tmp.Lx;
  coeffs[1] += tmp.Ky - tmp.Ly;
  coeffs[2] += -tmp.Lx;
}

void addInterim(Quad Q : Quad._11)(in Interim tmp, ref float[3] coeffs) {
  coeffs[0] += tmp.Kx - tmp.Lx;
  coeffs[1] += tmp.Ky - tmp.Ly;
  coeffs[2] += -tmp.Kx + tmp.Lx;
}


//------------------------------------------------------------------------------

void calcCoeffs(size_t K)(uint half, uint qidx, ref IPoint pos, ref FPoint[K] pts, ref float[3] coeffs) {
  switch (qidx) {
  case 0b00:
    // (0, 0)
    updateCoeffs!(K, Quad._00)(half, pts, coeffs);
    break;

  case 0b01:
    pos.x -= half;
    foreach(i; 0 .. K)
      pts[i].x -= half;
    updateCoeffs!(K, Quad._01)(half, pts, coeffs);
    break;

  case 0b10:
    pos.y -= half;
    foreach(i; 0 .. K)
      pts[i].y -= half;
    updateCoeffs!(K, Quad._10)(half, pts, coeffs);
    break;

  case 0b11:
    pos.x -= half;
    pos.y -= half;
    foreach(i; 0 .. K) {
      pts[i].x -= half;
      pts[i].y -= half;
    }
    updateCoeffs!(K, Quad._11)(half, pts, coeffs);
    break;

  default:
    assert(0);
  }
}