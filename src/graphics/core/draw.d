module graphics.core.draw;

import std.array, std.conv;
import core.stdc.string;
import guip.point, guip.rect, guip.size, guip.bitmap;
import graphics.core.blitter, graphics.core.fonthost, graphics.core.glyph, graphics.core.matrix,
    graphics.core.paint, graphics.core.path, graphics.core.path_detail.path_measure,
    graphics.core.pmcolor, graphics.core.shader, graphics.core.wavelet.wavelet;
import graphics.math.clamp, graphics.math.poly;

struct Draw
{
public:
    Bitmap _bitmap;
    Matrix _matrix;
    IRect _clip;

    this(Bitmap bitmap)
    {
        _bitmap = bitmap;
    }

    this(Bitmap bitmap, in Matrix matrix, in IRect clip)
    {
        this(bitmap);
        _matrix = matrix;
        _clip = clip;
    }

    void drawPaint(Paint paint)
    {
        auto ir = _bitmap.bounds;
        if (ir.intersect(_clip))
            getBlitter(paint).blitRect(ir);
    }

    private Blitter getBlitter(Paint paint)
    {
        return Blitter.Choose(_bitmap, _matrix, paint);
    }

    private Blitter getBlitter(Paint paint, in Bitmap source, IPoint ioff)
    {
        return Blitter.ChooseSprite(_bitmap, paint, source, ioff);
    }

    void drawColor(in Color c)
    {
        _bitmap.eraseColor(PMColor(c));
    }

    void drawPath(in Path path, Paint paint)
    {
        if (_clip.empty || path.empty)
            return;

        scope Blitter blitter = getBlitter(paint);
        waveletBlitPath(path, _clip, _matrix, &blitter.blitAlphaH);
    }

    void drawBitmap(in Bitmap source, Paint paint)
    {
        if (_clip.empty || source.bounds.empty ||
            source.config == Bitmap.Config.NoConfig ||
            paint.color.a == 0)
        {
            return;
        }

        auto ioff = IPoint(to!int(_matrix[0][2]), to!int(_matrix[1][2]));
        auto ir = IRect(ioff, ioff + source.size);

        if (_matrix.translativeOnly && source.config != Bitmap.Config.A8)
        {
            if (ir.intersect(_clip))
            {
                scope auto blitter = getBlitter(paint, source, ioff);
                blitter.blitRect(ir);
            }
        }
        else
        {
            if (source.config == Bitmap.Config.A8)
            {
                // TODO: need to apply transformation
                scope auto blitter = this.getBlitter(paint);
                blitter.blitMask(ioff.x, ioff.y, source);
            }
            else
            {
                Shader oldshader = paint.shader;
                scope(exit) paint.shader = oldshader;
                paint.shader = new BitmapShader(source);

                ir = IRect(source.size);
                drawRect(fRect(ir), paint);
            }
        }
    }

    void drawRect(in FRect rect, Paint paint)
    {
        FRect fr = rect;
        if (_clip.empty || !fr.intersect(fRect(_clip)))
            return;

        Path path;
        path.addRect(fr);
        drawPath(path, paint);
    }

    void drawText(string text, FPoint pt, TextPaint paint)
    {
        if (text.empty || _clip.empty ||
            paint.color.a == 0)
            return;

        auto backUp = _matrix;
        scope(exit) _matrix = backUp;

        auto cache = getGlyphCache(paint.typeFace, paint.textSize);

        float hOffset = 0;
        if (paint.textAlign != TextPaint.TextAlign.Left)
        {
            auto length = measureText(text, cache);
            if (paint.textAlign == TextPaint.TextAlign.Center)
                length *= 0.5;
            hOffset = length;
        }

        _matrix.preTranslate(pt.x, pt.y);
        Matrix scaledMatrix = _matrix;
        // TODO: scale matrix according to freetype outline relation
        // auto scale = PathGlyphStream.getScale();
        // scaledMatrix.preScale(scale, scale);

        FPoint pos = FPoint(0, 0);
        foreach(gl; cache.glyphStream(text, Glyph.LoadFlag.Metrics | Glyph.LoadFlag.Path))
        {
            Matrix m;
            m.setTranslate(pos.x - hOffset, 0);
            _matrix = scaledMatrix * m;
            drawPath(gl.path, paint);
            pos += gl.advance;
        }
    }

    void drawTextOnPath(string text, in Path follow, TextPaint paint)
    {
        auto meas = PathMeasure(follow);

        float hOffset = 0;
        if (paint.textAlign != TextPaint.TextAlign.Left)
        {
            auto length = meas.length;
            if (paint.textAlign == TextPaint.TextAlign.Center)
                length *= 0.5;
            hOffset = length;
        }

        //! TODO: scaledMatrix

        auto cache = getGlyphCache(paint.typeFace, paint.textSize);
        FPoint pos = FPoint(0, 0);
        foreach(gl; cache.glyphStream(text, Glyph.LoadFlag.Metrics | Glyph.LoadFlag.Path))
        {
            Matrix m;
            m.setTranslate(pos.x + hOffset, 0);
            this.drawPath(morphPath(gl.path, meas, m), paint);
            pos += gl.advance;
        }
    }

    private Path morphPath(in Path path, in PathMeasure meas, in Matrix matrix)
    {
        Path dst;

        foreach(verb, pts; path)
        {
            final switch(verb)
            {
            case Path.Verb.Move:
                FPoint[1] mpts = void;
                mpts[0] = pts[0];
                morphPoints(mpts, meas, matrix);
                dst.moveTo(mpts[0]);
                break;

            case Path.Verb.Line:
                //! use quad to allow curvature
                FPoint[2] mpts = void;
                mpts[0] = (pts[0] + pts[1]) * 0.5f;
                mpts[1] = pts[1];
                morphPoints(mpts, meas, matrix);
                dst.quadTo(mpts[0], mpts[1]);
                break;

            case Path.Verb.Quad:
                FPoint[2] mpts = void;
                memcpy(mpts.ptr, pts.ptr, 2 * FPoint.sizeof);
                morphPoints(mpts, meas, matrix);
                dst.quadTo(mpts[0], mpts[1]);
                break;

            case Path.Verb.Cubic:
                FPoint[3] mpts = void;
                memcpy(mpts.ptr, pts.ptr, 3 * FPoint.sizeof);
                morphPoints(mpts, meas, matrix);
                dst.cubicTo(mpts[0], mpts[1], mpts[2]);
                break;

            case Path.Verb.Close:
                dst.close();
                break;
            }
        }
        return dst;
    }

    private void morphPoints(size_t K)(ref FPoint[K] pts, in PathMeasure meas, in Matrix matrix)
    {
        matrix.mapPoints(pts);

        for (size_t i = 0; i < K; ++i)
        {
            FVector normal;
            auto pos = meas.getPosAndNormalAtDistance(pts[i].x, normal);
            pts[i] = pos - normal * pts[i].y;
        }
    }
};

void waveletBlitPath(in Path path, IRect clip, ref const Matrix mat, scope WaveletRaster.BlitDg dg)
{
    FRect bounds = mat.mapRect(path.bounds);
    auto ir = bounds.roundOut;

    debug
    {
        auto outer = ir;
        void checkPoints(FPoint[] pts)
        {
            foreach(pt; pts)
            {
                assert(fitsIntoRange!("[]")(pt.x, outer.left, outer.right)
                       && fitsIntoRange!("[]")(pt.y, outer.top, outer.bottom), std.conv.text(pt, " ", outer));
            }
        }
    }

    if (!ir.intersect(clip))
        return;
    WaveletRaster wr = WaveletRaster(ir);

    foreach(verb, pts; mat.perspective ? &path.apply!(QuadCubicFlattener) : &path.opApply)
    {
        final switch(verb)
        {
        case Path.Verb.Move:
        case Path.Verb.Close:
            break;

        case Path.Verb.Line:
            foreach(i; SIota!(0, 2))
                pts[i] = mat * pts[i];
            debug checkPoints(pts);
            wr.insertEdge(*cast(FPoint[2]*)pts.ptr);
            break;
        case Path.Verb.Quad:
            foreach(i; SIota!(0, 3))
                pts[i] = mat * pts[i];
            debug checkPoints(pts);
            wr.insertEdge(*cast(FPoint[3]*)pts.ptr);
            break;
        case Path.Verb.Cubic:
            foreach(i; SIota!(0, 4))
                pts[i] = mat * pts[i];
            debug checkPoints(pts);
            wr.insertEdge(*cast(FPoint[4]*)pts.ptr);
            break;
        }
    }
    wr.blit(dg);
}
