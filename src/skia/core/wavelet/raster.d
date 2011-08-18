module skia.core.wavelet.raster;

import std.algorithm, std.array, std.bitmanip, std.math, std.random, std.typecons, std.conv : to;
import std.datetime : benchmark, StopWatch;
import std.metastrings;
import skia.math.clamp, skia.math.rounding, skia.util.format, skia.bezier.chop,
  skia.core.edge_detail.algo, skia.core.path, skia.core.blitter,
  skia.core.matrix, skia.math.fixed_ary, skia.bezier.cartesian;
import guip.bitmap, guip.point, guip.rect, guip.size;
import qcheck._;

// version=DebugNoise;
// version=StackStats;
// version=calcCoeffs_C;

version (calcCoeffs_C) {
  extern(C) {
    void calcCoeffs_2(uint half, uint qidx, IPoint* pos, const FPoint* pts, float* coeffs);
    void calcCoeffs_3(uint half, uint qidx, IPoint* pos, const FPoint* pts, float* coeffs);
    void calcCoeffs_4(uint half, uint qidx, IPoint* pos, const FPoint* pts, float* coeffs);
  }
} else {
  import skia.core.wavelet.calc_coeffs;
  alias calcCoeffs!2 calcCoeffs_2;
  alias calcCoeffs!3 calcCoeffs_3;
  alias calcCoeffs!4 calcCoeffs_4;
}

struct Node {
  @property string toString() const {
    auto str = fmtString("Node coeffs:%s", coeffs);
    foreach(i; 0 .. 4)
      if (hasChild(i))
        str ~= fmtString("\n%d:%s", i, children[i].toString());
    return str;
  }

  void insertEdge(size_t K)(IPoint pos, FPoint[K] pts, uint depth)
  in {
    fitsIntoRange!("[)")(pos.x, 0, 1 << depth);
    fitsIntoRange!("[)")(pos.y, 0, 1 << depth);
  } body {

    auto node = &this;
    for(;;) {

      debug {
        foreach(pt; pts)
          assert(fitsIntoRange!("[]")(pt.x, -1e-1, (1<<depth+1)+1e-1)
                 && fitsIntoRange!("[]")(pt.y, -1e-1, (1<<depth+1)+1e-1),
                 to!string(pts) ~ "|" ~ to!string(depth));
      }

      const half = 1 << --depth;
      const right = pos.x >= half;
      const bottom = pos.y >= half;
      const qidx = bottom << 1 | right;

      version (calcCoeffs_C)
        mixin(Format!(q{calcCoeffs_%s(half, qidx, &pos, pts.ptr, node.coeffs.ptr);}, K));
      else
        calcCoeffs!K(half, qidx, pos, pts, node.coeffs);

      if (depth == 0)
        break;
      node = &node.getChild(depth, qidx);
    }
  }

  ref Node getChild(uint depth, uint idx) {
    assert(depth > 0);
    assert(children.length == 0 || children.length == 4 || children.length == 20);

    if (children.length == 0) {
      children = allocNodes!(4)();
    }
    this.chmask |= (1 << idx);
    return children[idx];
  }

  bool hasChild(uint idx) const {
    return (this.chmask & (1 << idx)) != 0;
  }

  static Node[] allocNodes(size_t K)() {
    debug {
      size_t olen = segStack.data.length;
      scope(exit) assert(segStack.data.length == olen + K);
    }

    foreach(_; 0 .. K) {
      segStack.put(Node.init);
    }
    return segStack.data[$-K .. $];
  }

  static Appender!(Node[]) segStack;

  static void clearSegStack() {
    version(StackStats) stats ~= segStack.capacity * Node.sizeof;
    segStack.clear();
  }

  version(StackStats) {
    static size_t[] stats;

    static ~this() {
      std.stdio.writeln("Node stack stats:");
      std.stdio.writeln("num uses:", stats.length);
      std.stdio.writeln("stack cap:", segStack.capacity * Node.sizeof);
      auto avg = reduce!("a+b")(0.0, stats) / stats.length;
      std.stdio.writeln("avg:", avg);
      double dev = 0.0;
      foreach(st; stats)
        dev += (st - avg) * (st - avg);
      dev = sqrt(dev / stats.length);
      std.stdio.writeln("dev:", dev);
    }
  }

  Node[] children;
  float[3] coeffs = 0.0f;
  ubyte chmask;
}


struct WaveletRaster {

  this(IRect clipRect) {
    this.depth = to!uint(ceil(log2(max(clipRect.width, clipRect.height))));
    this.clipRect = clipRect;
    Node.clearSegStack();
  }

  void insertSlice(size_t K)(IPoint pos, ref FPoint[K] slice) if (K == 2) {
    this.rootConst += (1.f / (1 << this.depth) ^^ 2) * determinant(slice[0], slice[1]) / 2;
    if (this.depth)
      this.root.insertEdge(pos, slice, this.depth);
  }

  void insertSlice(size_t K)(IPoint pos, ref FPoint[K] slice) if (K == 3) {
    this.rootConst += (1.f / (6.f * (1 << this.depth) ^^ 2)) * (
        2 * (determinant(slice[0], slice[1]) + determinant(slice[1], slice[2]))
        + determinant(slice[0], slice[2]));
    if (this.depth)
      root.insertEdge(pos, slice, depth);
  }

  void insertSlice(size_t K)(IPoint pos, ref FPoint[K] slice) if (K == 4) {
    this.rootConst += (1.f / (20.f * (1 << this.depth) ^^ 2)) * (
        6 * determinant(slice[0], slice[1]) + 3 * determinant(slice[1], slice[2])
        + 6 * determinant(slice[2], slice[3]) + 3 * determinant(slice[0], slice[2])
        + 3 * determinant(slice[1], slice[3]) + 1 * determinant(slice[0], slice[3])
    );
    if (this.depth)
      root.insertEdge(pos, slice, this.depth);
  };

  void insertEdge(FPoint[2] pts) {
    //    assert(pointsAreClipped(pts));
    foreach(ref pt; pts)
      pt -= fPoint(this.clipRect.pos);
    cartesianBezierWalker(pts, FRect(fRect(this.clipRect).size), FSize(1, 1), &this.insertSlice!2, &this.insertSlice!2);
  }

  void insertEdge(FPoint[3] pts) {
    //    assert(pointsAreClipped(pts));
    foreach(ref pt; pts)
      pt -= fPoint(this.clipRect.pos);
    cartesianBezierWalker(pts, FRect(fRect(this.clipRect).size), FSize(1, 1), &this.insertSlice!3, &this.insertSlice!2);
  }

  void insertEdge(FPoint[4] pts) {
    //    assert(pointsAreClipped(pts), to!string(pts));
    foreach(ref pt; pts)
      pt -= fPoint(this.clipRect.pos);
    cartesianBezierWalker(pts, FRect(fRect(this.clipRect).size), FSize(1, 1), &this.insertSlice!4, &this.insertSlice!2);
  }

  bool pointsAreClipped(in FPoint[] pts) {
    foreach(pt; pts)
      if (!fitsIntoRange!("[]")(pt.x, 0.0f, 1.0f) || !fitsIntoRange!("[]")(pt.y, 0.0f, 1.0f))
        return false;

    return true;
  }

  Node root;
  float rootConst = 0.0f;
  uint depth;
  IRect clipRect;
}

void writeGridValue(alias blit)(float val, IPoint off, uint locRes) {
  assert(locRes > 0);
  version(DebugNoise) {
    enum noise = 55;
    auto ubval = clampTo!ubyte(abs(val * (255-noise)) + uniform(0, noise));
  } else {
    auto ubval = clampTo!ubyte(abs(val * 255));
  }
  if (ubval == 0)
    return;

  auto left = off.x;
  auto right = off.x + locRes;
  foreach(y; off.y .. off.y + locRes) {
    blit(y, left, right, ubval);
  }
}

void writeNodeToGrid(alias blit, alias timeout=false)
(in Node n, float val, IPoint offset, uint locRes)
{
  // Can happen with only the root node on very small paths
  if (locRes == 1) {
    writeGridValue!blit(val, offset, locRes);
    return;
  }
  assert(locRes > 1);
  uint locRes2 = locRes / 2;
  bool blitLowRes = timeout;

  auto cval = val + n.coeffs[0]  + n.coeffs[1] + n.coeffs[2];
  if (!blitLowRes && n.hasChild(0))
    writeNodeToGrid!blit(n.children[0], cval, offset, locRes2);
  else
    writeGridValue!blit(cval, offset, locRes2);

  cval = val - n.coeffs[0] + n.coeffs[1] - n.coeffs[2];
  offset.x += locRes2;
  if (!blitLowRes && n.hasChild(1))
    writeNodeToGrid!blit(n.children[1], cval, offset, locRes2);
  else
    writeGridValue!blit(cval, offset, locRes2);

  cval = val + n.coeffs[0] - n.coeffs[1] - n.coeffs[2];
  offset.x -= locRes2;
  offset.y += locRes2;
  if (!blitLowRes && n.hasChild(2))
    writeNodeToGrid!blit(n.children[2], cval, offset, locRes2);
  else
    writeGridValue!blit(cval, offset, locRes2);

  cval = val - n.coeffs[0] - n.coeffs[1] + n.coeffs[2];
  offset.x += locRes2;
  if (!blitLowRes && n.hasChild(3))
    writeNodeToGrid!blit(n.children[3], cval, offset, locRes2);
  else
    writeGridValue!blit(cval, offset, locRes2);
}

void blitEdges(in Path path, IRect clip, Blitter blitter, int ystart, int yend) {
  auto wr = pathToWavelet(path, clip);
  auto topLeft = wr.clipRect.pos;
  void blitRow(int y, int xstart, int xend, ubyte alpha) {
    if (fitsIntoRange!("[)")(y, max(ystart, clip.top), min(yend, clip.bottom))) {
      blitter.blitAlphaH(y, clampToRange(xstart, clip.left, clip.right), clampToRange(xend, clip.left, clip.right), alpha);
    }
  }
  writeNodeToGrid!(blitRow)(
      wr.root, wr.rootConst, topLeft, 1<< wr.depth);
}

WaveletRaster pathToWavelet(in Path path, IRect clip) {
  auto ir = path.ibounds;
  if (!ir.intersect(clip))
    return WaveletRaster.init;
  WaveletRaster wr = WaveletRaster(ir);

  path.forEach((Path.Verb verb, in FPoint[] pts) {
      final switch(verb) {
      case Path.Verb.Move, Path.Verb.Close:
        break;
      case Path.Verb.Line:
        wr.insertEdge(fixedAry!2(pts));
        break;
      case Path.Verb.Quad:
        wr.insertEdge(fixedAry!3(pts));
        break;
      case Path.Verb.Cubic:
        wr.insertEdge(fixedAry!4(pts));
        break;
      }
    });
  return wr;
}
