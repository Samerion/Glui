///
module glui.image_view;

import glui.node;
import glui.utils;
import glui.style;
import glui.backend;

alias imageView = simpleConstructor!GluiImageView;

@safe:

/// A node specifically to display images.
///
/// The image will automatically scale to fit available space. It will keep aspect ratio by default and will be
/// displayed in the middle of the available box.
class GluiImageView : GluiNode {

    mixin DefineStyles;

    public {

        /// If true, size of this imageView is adjusted automatically. Changes made to `minSize` will be reversed on
        /// size update.
        bool isSizeAutomatic;

    }

    protected {

        /// Texture for this node.
        Texture _texture;

        /// If set, path in the filesystem the texture is to be loaded from.
        string _texturePath;

        /// Rectangle occupied by this node after all calculations.
        Rectangle _targetArea;

    }

    /// Set to true if the image view owns the texture and manages its ownership.
    private bool _isOwner;

    deprecated("Use this(NodeParams, T, Vector2) instead.") {

        static foreach (index; 0 .. BasicNodeParamLength) {

            /// Create an image node from given texture or filename.
            /// Params:
            ///     source  = `Texture` raylib struct to use, or a filename to load from.
            ///     minSize = Minimum size of the node.
            this(T)(BasicNodeParam!index sup, T source, Vector2 minSize = Vector2(0, 0)) {

                super(sup);
                texture = source;
                super.minSize = minSize;

            }

        }

    }

    /// Create an image node from given texture or filename.
    ///
    /// Note, if a string is given, the texture will be loaded when resizing. This ensures a Glui backend is available
    /// to load the texture.
    ///
    /// Params:
    ///     source  = `Texture` struct to use, or a filename to load from.
    ///     minSize = Minimum size of the node. Defaults to image size.
    this(T)(NodeParams sup, T source, Vector2 minSize) {

        super(sup);
        super.minSize = minSize;
        this.texture = source;

    }

    /// ditto
    this(T)(NodeParams sup, T source) {

        super(sup);
        super.minSize = minSize;
        this.texture = source;
        this.isSizeAutomatic = true;

    }

    ~this() {

        clear();

    }

    @property {

        /// Set the texture.
        Texture texture(Texture texture) {

            clear();
            _isOwner = false;
            _texturePath = null;

            return this._texture = texture;

        }

        /// Load the texture from a filename.
        string texture(string filename) @trusted {

            import std.string : toStringz;

            _texturePath = filename;

            if (tree) {

                clear();
                _texture = tree.io.loadTexture(filename);
                _isOwner = true;

            }

            updateSize();

            return filename;

        }

        unittest {

            auto io = new HeadlessBackend;
            auto root = imageView(.nullTheme, "logo.png");

            // The texture will lazy-load
            assert(root.texture == Texture.init);

            root.io = io;
            root.draw();

            // Texture should be loaded by now
            assert(root.texture != Texture.init);

            io.assertTexture(root.texture, Vector2(0, 0), color!"fff");

        }

        /// Get the current texture.
        const(Texture) texture() const {

            return _texture;

        }

    }

    /// Remove any texture if attached.
    void clear() @trusted scope {

        // Free the texture
        if (_isOwner) {

            _texture.destroy();

        }

        // Remove the texture
        _texture = texture.init;

    }

    /// Minimum size of the image.
    @property
    ref inout(Vector2) minSize() inout {

        return super.minSize;

    }

    /// Area on the screen the image was last drawn to.
    @property
    Rectangle targetArea() const {

        return _targetArea;

    }

    override protected void resizeImpl(Vector2 space) @trusted {

        // Lazy-load the texture if the backend wasn't present earlier
        if (_texture == _texture.init && _texturePath) {

            _texture = tree.io.loadTexture(_texturePath);
            _isOwner = true;

        }

        // Adjust size
        if (isSizeAutomatic) {

            minSize = _texture.viewportSize;

        }

    }

    override protected void drawImpl(Rectangle, Rectangle rect) @trusted {

        import std.algorithm : min;

        // Ignore if there is no texture to draw
        if (texture.id <= 0) return;

        // Get the scale
        const scale = min(
            rect.width / texture.width,
            rect.height / texture.height
        );

        const size     = Vector2(texture.width * scale, texture.height * scale);
        const position = center(rect) - size/2;

        _targetArea = Rectangle(position.tupleof, size.tupleof);
        _texture.draw(position);

    }

    override protected bool hoveredImpl(Rectangle, Vector2 mouse) const {

        return _targetArea.contains(mouse);

    }

    override inout(Style) pickStyle() inout {

        return null;

    }

}
