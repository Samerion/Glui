module glui.typeface;

import bindbc.freetype;

import std.range;
import std.traits;
import std.string;
import std.algorithm;

import glui.utils;
import glui.backend;


@safe:


/// Low-level interface for drawing text. Represents a single typeface.
///
/// Unlike the rest of Glui, Typeface doesn't define pixels as 1/96th of an inch. DPI must also be specified manually.
///
/// See: [glui.text.Text] for an interface on a higher level.
interface Typeface {

    /// List glyphs  in the typeface.
    long glyphCount() const;

    /// Get initial pen position.
    Vector2 penPosition() const;

    /// Get line height.
    int lineHeight() const;

    /// Get advance vector for the given glyph. Uses dots, not pixels, as the unit.
    Vector2 advance(dchar glyph) const;

    /// Set font scale. This should be called at least once before drawing.
    ///
    /// Font renderer should cache this and not change the scale unless updated.
    ///
    /// Params:
    ///     scale = Horizontal and vertical DPI value, for example (96, 96)
    Vector2 dpi(Vector2 scale);

    /// Get curently set DPI.
    Vector2 dpi() const;

    /// Draw a line of text.
    /// Note: This API is unstable and might change over time.
    void drawLine(ref Image target, ref Vector2 penPosition, string text, Color tint) const;

    /// Get the default Glui typeface.
    static defaultTypeface() => FreetypeTypeface.defaultTypeface;

    /// Default word splitter used by measure/draw.
    final defaultWordChunks(Range)(Range range) const {

        import std.uni;

        /// Pick the group the character belongs to.
        static bool pickGroup(dchar a) {

            return a.isAlphaNum || a.isPunctuation;

        }

        return range
            .splitWhen!((a, b) => pickGroup(a) != pickGroup(b) && !b.isWhite)
            .map!"text(a)"
            .cache;
        // TODO string allocation could probably be avoided

    }

    /// Measure space the given text would span. Uses dots as the unit.
    ///
    /// If `availableSpace` is specified, assumes text wrapping. Text wrapping is only performed on whitespace
    /// characters.
    ///
    /// Params:
    ///     chunkWords = Algorithm to use to break words when wrapping text; separators must be preserved.
    ///     availableSpace = Amount of available space the text can take up (dots), used to wrap text.
    ///     text = Text to measure.
    ///     wrap = Toggle text wrapping.
    final Vector2 measure(alias chunkWords = defaultWordChunks, String)
        (Vector2 availableSpace, String text, bool wrap = true) const
    if (isSomeString!String)
    do {

        // Wrapping off
        if (!wrap) return measure(text);

        auto ruler = TextRuler(this, availableSpace.x);

        // TODO don't fail on decoding errors
        // TODO RTL layouts
        // TODO vertical text
        // TODO lineSplitter removes the last line feed if present, which is unwanted behavior

        // Split on lines
        foreach (line; text.lineSplitter) {

            ruler.startLine();

            // Split on words
            foreach (word; chunkWords(line)) {

                ruler.addWord(word);

            }

        }

        return ruler.textSize;

    }

    /// ditto
    final Vector2 measure(String)(String text) const
    if (isSomeString!String)
    do {

        // No wrap, only explicit in-text line breaks

        auto ruler = TextRuler(this);

        // TODO don't fail on decoding errors

        // Split on lines
        foreach (line; text.lineSplitter) {

            ruler.startLine();
            ruler.addWord(line);

        }

        return ruler.textSize;

    }

    /// Draw text within the given rectangle in the image.
    final void draw(alias chunkWords = defaultWordChunks, String)
        (ref Image image, Rectangle rectangle, String text, Color tint, bool wrap = true)
    const {

        auto ruler = TextRuler(this, rectangle.w);

        // TODO decoding errors

        // Text wrapping on
        if (wrap) {

            // Split on lines
            foreach (line; text.lineSplitter) {

                ruler.startLine();

                // Split on words
                foreach (word; chunkWords(line)) {

                    auto penPosition = rectangle.start + ruler.addWord(word);

                    drawLine(image, penPosition, word, tint);

                }

            }

        }

        // Text wrapping off
        else {

            // Split on lines
            foreach (line; text.lineSplitter) {

                ruler.startLine();

                auto penPosition = rectangle.start + ruler.addWord(line);

                drawLine(image, penPosition, line, tint);

            }

        }

    }

}

/// Low level interface for measuring text.
struct TextRuler {

    /// Typeface to use for the text.
    const Typeface typeface;

    /// Maximum width for a single line. If `NaN`, no word breaking is performed.
    float lineWidth;

    /// Current pen position.
    Vector2 penPosition;

    /// Total size of the text.
    Vector2 textSize;

    this(const Typeface typeface, float lineWidth = float.nan) {

        this.typeface = typeface;
        this.lineWidth = lineWidth;

        penPosition = typeface.penPosition - typeface.lineHeight;

    }

    /// Begin a new line.
    void startLine() {

        const lineHeight = typeface.lineHeight;

        // Move the pen to the next line
        penPosition.x = 0;
        penPosition.y += lineHeight;
        textSize.y += lineHeight;

    }

    /// Add the given word to the text. The text must be single line.;
    /// Returns: Pen position for the word.
    Vector2 addWord(String)(String word) {

        const maxWordWidth = lineWidth - penPosition.x;

        float wordSpan = 0;

        // Measure each glyph
        foreach (dchar glyph; word) {

            wordSpan += typeface.advance(glyph).x;

        }

        // Exceeded line width
        // Automatically false if lineWidth is NaN
        if (maxWordWidth < wordSpan && wordSpan < lineWidth) {

            // Start a new line
            startLine();

        }

        const wordPosition = penPosition;

        // Update pen position
        penPosition.x += wordSpan;

        // Allocate space
        if (penPosition.x > textSize.x) textSize.x = penPosition.x;

        return wordPosition;

    }

}

/// Represents a freetype2-powered typeface.
class FreetypeTypeface : Typeface {

    public {

        /// Underlying face.
        FT_Face face;

    }

    private {

        /// If true, this typeface has been loaded using this class, making the class responsible for freeing the font.
        bool _isOwner;

        /// Font size loaded (points).
        int _size;

        /// Current DPI set for the typeface.
        int _dpiX, _dpiY;

    }

    static FreetypeTypeface defaultTypeface;

    /// Use an existing freetype2 font.
    this(FT_Face face, int size) {

        this.face = face;
        this._size = size;

    }

    /// Load a font from a file.
    /// Params:
    ///     backend  = I/O Glui backend, used to adjust the scale of the font.
    ///     filename = Filename of the font file.
    ///     size     = Size of the font to load (in points).
    this(string filename, int size) @trusted {

        this._isOwner = true;
        this._size = size;

        // TODO proper exceptions
        if (auto error = FT_New_Face(freetype, filename.toStringz, 0, &this.face)) {

            throw new Exception(format!"Failed to load `%s`, error no. %s"(filename, error));

        }

    }

    ~this() @trusted {

        // Ignore if the resources used by the class have been borrowed
        if (!_isOwner) return;

        FT_Done_Face(face);

    }

    bool isOwner() const => _isOwner;
    bool isOwner(bool value) @system => _isOwner = value;

    long glyphCount() const {

        return face.num_glyphs;

    }

    /// Get initial pen position.
    Vector2 penPosition() const {

        return Vector2(0, face.size.metrics.ascender) / 64;

    }

    /// Line height.
    int lineHeight() const {

        // +1 is an error margin
        return cast(int) (face.size.metrics.height / 64) + 1;

    }

    Vector2 dpi() const {

        return Vector2(_dpiX, _dpiY);

    }

    Vector2 dpi(Vector2 dpi) @trusted {

        const dpiX = cast(int) dpi.x;
        const dpiY = cast(int) dpi.y;

        // Ignore if there's no change
        if (dpiX == _dpiX && dpiY == _dpiY) return dpi;

        _dpiX = dpiX;
        _dpiY = dpiY;

        // Load size
        if (auto error = FT_Set_Char_Size(face, 0, _size*64, dpiX, dpiY)) {

            throw new Exception(
                format!"Failed to load font at size %s at DPI %sx%s, error no. %s"(_size, dpiX, dpiY, error)
            );

        }

        return dpi;

    }

    /// Get advance vector for the given glyph
    Vector2 advance(dchar glyph) const @trusted {

        assert(_dpiX && _dpiY, "Font DPI hasn't been set");

        // Sadly, there is no way to make FreeType operate correctly in `const` environment.

        // Load the glyph
        if (auto error = FT_Load_Char(cast(FT_FaceRec*) face, glyph, FT_LOAD_DEFAULT)) {

            return Vector2(0, 0);

        }

        // Advance the cursor position
        // TODO RTL layouts
        return Vector2(face.glyph.advance.tupleof) / 64;

    }

    /// Draw a line of text
    void drawLine(ref Image target, ref Vector2 penPosition, string text, Color tint) const @trusted {

        assert(_dpiX && _dpiY, "Font DPI hasn't been set");

        foreach (dchar glyph; text) {

            // Load the glyph
            if (auto error = FT_Load_Char(cast(FT_FaceRec*) face, glyph, FT_LOAD_RENDER)) {

                continue;

            }

            const bitmap = face.glyph.bitmap;

            assert(bitmap.pixel_mode == FT_PIXEL_MODE_GRAY);

            // Draw it to the image
            foreach (y; 0..bitmap.rows) {

                foreach (x; 0..bitmap.width) {

                    // Each pixel is a single byte
                    const pixel = *cast(ubyte*) (bitmap.buffer + bitmap.pitch*y + x);

                    const targetX = cast(int) penPosition.x + face.glyph.bitmap_left + x;
                    const targetY = cast(int) penPosition.y - face.glyph.bitmap_top + y;

                    // Don't draw pixels out of bounds
                    if (targetX >= target.width || targetY >= target.height) continue;

                    // Note: ImageDrawPixel overrides the pixel — alpha blending has to be done by us
                    const oldColor = target.get(targetX, targetY);
                    const newColor = tint.setAlpha(cast(float) pixel / pixel.max);
                    const color = alphaBlend(oldColor, newColor);

                    target.get(targetX, targetY) = color;

                }

            }

            // Advance pen positon
            penPosition += Vector2(face.glyph.advance.tupleof) / 64;

        }

    }

}

/// Font rendering via Raylib. Discouraged, potentially slow, and not HiDPI-compatible. Use `FreetypeTypeface` instead.
version (Have_raylib_d)
class RaylibTypeface : Typeface {

    import raylib;

    public {

        /// Character spacing, as a fraction of the font size.
        float spacing = 0.1;

        /// Line height relative to font height.
        float relativeLineHeight = 1.4;

        /// Scale to apply for the typeface.
        float scale = 1.0;

    }

    private {

        /// Underlying Raylib font.
        Font _font;

        /// If true, this is the default font, and has to be available ahead of time.
        ///
        /// If the typeface is requested before Raylib is loaded (...and it is...), the default font won't be available,
        /// so we must use late loading.
        bool _isDefault;

        /// If true, this typeface has been loaded using this class, making the class responsible for freeing the font.
        bool _isOwner;

    }

    /// Object holding the default typeface.
    static RaylibTypeface defaultTypeface() @trusted {

        static RaylibTypeface typeface;

        // Load the typeface
        if (!typeface) {
            typeface = new RaylibTypeface(GetFontDefault);
            typeface._isDefault = true;
            typeface.scale = 2.0;
        }

        return typeface;

    }

    /// Load a Raylib font.
    this(Font font) {

        this._font = font;

    }

    /// Load a Raylib font from file.
    deprecated("Raylib font rendering is inefficient and lacks scaling. Use FreetypeTypeface instead")
    this(string filename, int size) @trusted {

        this._font = LoadFontEx(filename.toStringz, size, null, 0);
        this.isOwner = true;

    }

    ~this() @trusted {

        if (isOwner) {

            UnloadFont(_font);

        }

    }

    Font font() @trusted {

        if (_isDefault)
            return _font = GetFontDefault;
        else
            return _font;

    }

    const(Font) font() const @trusted {

        if (_isDefault)
            return GetFontDefault;
        else
            return _font;

    }

    bool isOwner() const => _isOwner;
    bool isOwner(bool value) @system => _isOwner = value;

    /// List glyphs  in the typeface.
    long glyphCount() const {

        return font.glyphCount;

    }

    /// Get initial pen position.
    Vector2 penPosition() const {

        return Vector2(0, 0);

    }

    /// Get font height in pixels.
    int fontHeight() const {

        return cast(int) (font.baseSize * scale);

    }

    /// Get line height in pixels.
    int lineHeight() const {

        return cast(int) (fontHeight * relativeLineHeight);

    }

    /// Changing DPI at runtime is not supported for Raylib typefaces.
    Vector2 dpi(Vector2 dpi) {

        // Not supported for Raylib typefaces.
        return Vector2(96, 96);

    }

    Vector2 dpi() const {

        return Vector2(96, 96);

    }

    /// Get advance vector for the given glyph.
    Vector2 advance(dchar codepoint) const @trusted {

        const glyph = GetGlyphInfo(cast() font, codepoint);
        const spacing = fontHeight * this.spacing;
        const baseAdvanceX = glyph.advanceX
            ? glyph.advanceX
            : glyph.offsetX + glyph.image.width;
        const advanceX = baseAdvanceX * scale;

        return Vector2(advanceX + spacing, 0);

    }

    /// Draw a line of text
    /// Note: This API is unstable and might change over time.
    void drawLine(ref glui.backend.Image target, ref Vector2 penPosition, string text, Color tint) const @trusted {

        // Note: `DrawTextEx` doesn't scale `spacing`, but `ImageDrawTextEx` DOES. The image is first drawn at base size
        //       and *then* scaled.
        const spacing = font.baseSize * this.spacing;

        // We trust Raylib will not mutate the font
        // Raylib is single-threaded, so it shouldn't cause much harm anyway...
        auto font = cast() this.font;

        // Make a Raylib-compatible wrapper for image data
        auto result = target.toRaylib;

        ImageDrawTextEx(&result, font, text.toStringz, penPosition, fontHeight, spacing, tint);

    }

}

shared static this() @system {

    // Ignore if freetype was already loaded
    if (isFreeTypeLoaded) return;

    // Load freetype
    FTSupport ret = loadFreeType();

    // Check version
    if (ret != ftSupport) {

        if (ret == FTSupport.noLibrary) {

            assert(false, "freetype2 failed to load");

        }
        else if (FTSupport.badLibrary) {

            assert(false, format!"found freetype2 is of incompatible version %s (needed %s)"(ret, ftSupport));

        }

    }

}

static this() @trusted {

    // Load the font
    const typefaceFile = cast(ubyte[]) import("ruda-regular.ttf");

    FT_Face typeface;

    if (auto error = FT_New_Memory_Face(freetype, typefaceFile.ptr, typefaceFile.length, 0, &typeface)) {

        assert(false, format!"Failed to load default Glui typeface, error no. %s"(error));

    }

    // Set the default typeface
    FreetypeTypeface.defaultTypeface = new FreetypeTypeface(typeface, 14);
    FreetypeTypeface.defaultTypeface.isOwner = true;

}

/// Get the thread-local freetype reference.
FT_Library freetype() @trusted {

    static FT_Library library;

    // Load the library
    if (library != library.init) return library;

    if (auto error = FT_Init_FreeType(&library)) {

        assert(false, format!"Failed to load freetype2: %s"(error));

    }

    return library;

}
