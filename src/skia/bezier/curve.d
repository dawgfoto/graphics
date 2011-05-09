module skia.bezier.curve;

import guip.point;
import skia.math.clamp;

Point!T evalBezier(T)(Point!T[2] line, double t) {
  assert(fitsIntoRange!("[]")(t, 0.0, 1.0));
  return line[0] * (1 - t) + line[1] * t;
}

Point!T evalBezier(T)(Point!T[3] quad, double t) {
  assert(fitsIntoRange!("[]")(t, 0.0, 1.0));
  const mt = 1 - t;
  return quad[0] * (mt * mt) + quad[1] * (2 * mt * t) + quad[2] * (t * t);
}

Point!T evalBezier(T)(Point!T[4] cubic, double t) {
  assert(fitsIntoRange!("[]")(t, 0.0, 1.0));
  const mt = 1 - t;
  return cubic[0] * (mt * mt * mt) + cubic[1] * (3 * mt * mt * t)
    + cubic[2] * (3 * mt * t * t) + cubic[3] * (t * t * t);
}


Vector!T evalBezierDer(T)(Point!T[2] line, double t) {
  return line[1] - line[0];
}

Vector!T evalBezierDer(T)(Point!T[3] quad, double t) {
  return ((quad[1] - quad[0]) * (1 - t) + (quad[2] - quad[1]) * t) * 2;
}

Vector!T evalBezierDer(T)(Point!T[4] cubic, double t) {
  const mt = 1 - t;
  return ((cubic[1] - cubic[0]) * (mt * mt) + (cubic[2] - cubic[1]) * (2 * mt * t)
          + (cubic[3] - cubic[2]) * (t * t)) * 3;
}