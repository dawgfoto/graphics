module skia.core.bitmap;

private {
  import std.range : outputRangeObject;

  import skia.core.color;
  import skia.core.rect;
  import skia.core.size;
}


debug=PRINTF;
debug(PRINTF) import std.stdio : writeln, printf;

////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

enum Config {
  NoConfig,   //!< bitmap has not been configured
  A1,         //!< 1-bit per pixel, (0 is transparent, 1 is opaque)
  A8,         //!< 8-bits per pixel, with only alpha specified (0 is
              //!< transparent, 0xFF is opaque)
  Index8,     //!< 8-bits per pixel, using SkColorTable to specify the colors
  RGB_565,    //!< 16-bits per pixel, (see SkColorPriv.h for packing)
  ARGB_4444,  //!< 16-bits per pixel, (see SkColorPriv.h for packing)
  ARGB_8888,  //!< 32-bits per pixel, (see SkColorPriv.h for packing)
  RLE_Index8,
};

/**
   stub ColorTable
*/
class ColorTable
{
  enum
  {
    kColorsAreOpaque_Flag,
  }
  ubyte flags;
}

/**
   Bitmap
 */
class Bitmap {
  @property uint width;
  @property uint height;
  @property ISize size() const {
    return ISize(this.width, this.height);
  }
  @property IRect bounds() const {
    return IRect(this.size);
  }

  Config config;
  ubyte flags;
  ColorTable colorTable;
  // TODO: different storage for kA1Config needed
  PMColor[] buffer;

  this() {
    this(Config.NoConfig, 0, 0);
  }
  this(Config config, uint width, uint height) {
    this.setConfig(config, width, height);
  }

  void setConfig(Config config, uint width, uint height) {
    this.width = width;
    this.height = height;
    this.config = config;
    this.buffer.length = width * height;
  }

  void* getPixels() {
    assert(buffer);
    return buffer.ptr;
  }

  auto getRange(int x, int y) {
    //assert(x <= this.width);
    //assert(y <= this.height);
    size_t begin = y * this.width + x;
    return this.buffer[begin .. $];
  }

  @property void opaque(bool isOpaque) {
    if (isOpaque) {
      flags |= Flags.kImageIsOpaque_Flag;
    }
    else {
      flags &= ~Flags.kImageIsOpaque_Flag;
    }
  }

  @property bool opaque() const {
    final switch (this.config) {
        case Config.NoConfig:
            return true;

        case Config.A1:
        case Config.A8:
        case Config.ARGB_4444:
        case Config.ARGB_8888:
            return (this.flags & Flags.kImageIsOpaque_Flag) != 0;

        case Config.Index8:
        case Config.RLE_Index8: {
	  // if lockPixels failed, we may not have a ctable ptr
	  return this.colorTable &&
	    ((this.colorTable.flags
	     & ColorTable.kColorsAreOpaque_Flag) != 0);
	}

        case Config.RGB_565:
            return true;
    }
  }

  void eraseColor(PMColor c) {
    if (0 == this.width || 0 == this.height
	|| this.config == Config.NoConfig
	|| this.config == Config.Index8)
      return;

    assert(this.config == Config.ARGB_8888);
    this.buffer[] = c;
    // this.notifyPixelChanged();
  }

private:

  enum Flags
  {
    kImageIsOpaque_Flag = 0x01,
  }
}

/++
size_t RowBytes(Config c, int width) {
  assert(width > 0);
  return c == Config.A1 ? (width + 7) >> 3 : width * BytesPerPixel(c);
}

uint BytesPerPixel(Config c) {
  final switch (c) {
  case Config.NoConfig, Config.A1:
    return 0;
  case Config.RLE_Index8, Config.A8, Config.Index8:
    return 1;
  case Config.RGB_565, Config.ARGB_4444:
    return 2;
  case Config.ARGB_8888:
    return 4;
  }
}
+/
