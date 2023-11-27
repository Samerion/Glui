module glui.text;

import raylib;
import std.algorithm;

import glui.node;
import glui.style;
import glui.typeface;


@safe:


/// Draws text: handles updates, formatting and styling.
struct Text(T : GluiNode) {

    /// Node owning this text struct.
    T node;

    /// Texture generated by the struct.
    /// Note: Lifetime of the texture is managed by the struct.
    Texture2D texture;

    /// Underlying text.
    string value;

    alias value this;

    this(T node, string text) {

        this.node = node;
        opAssign(text);

    }

    ~this() @trusted {

        if (!__ctfe && IsWindowReady) {

            UnloadTexture(texture);

        }

    }

    string opAssign(string text) {

        // Ignore if there's no change to be made
        if (text == value) return text;

        // Request update otherwise
        node.updateSize;
        return value = text;

    }

    /// Get the size of the text.
    Vector2 size() const {

        return Vector2(texture.width, texture.height);

    }

    alias minSize = size;

    /// Set new bounding box for the text and redraw it.
    void resize() {

        const style = node.pickStyle;
        const size = style.typeface.measure(value);

        resizeImpl(style, size, false);

    }

    /// Set new bounding box for the text; wrap the text if it doesn't fit in boundaries. Redraw it.
    void resize(alias splitter = Typeface.defaultWordChunks)(Vector2 space, bool wrap = true) {

        const style = node.pickStyle;
        const size = style.typeface.measure!splitter(space, value, wrap);

        resizeImpl(style, size, wrap);

    }

    private void resizeImpl(const Style style, Vector2 size, bool wrap) @trusted {

        // Empty, nothing to do
        if (size.x < 1 || size.y < 1) return;

        auto image = GenImageColor(
            cast(int) size.x,
            cast(int) size.y,
            Colors.BLANK,
        );

        scope (exit) UnloadImage(image);

        // TODO text wrap
        style.drawText(image, Rectangle(0, 0, size.tupleof), value, wrap);

        // Destroy old texture if needed
        if (texture !is texture.init) {

            UnloadTexture(texture);

        }

        // Load texture
        texture = LoadTextureFromImage(image);


    }

    /// Draw the text.
    void draw(Vector2 position) @trusted {

        if (texture !is texture.init) {

            DrawTexture(texture, cast(int) position.x, cast(int) position.y, Colors.WHITE);

        }

    }

    void draw(Rectangle rectangle) {

        draw(Vector2(rectangle.x, rectangle.y));

    }

    string toString() const {

        return value;

    }

}
