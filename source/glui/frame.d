///
module glui.frame;

import raylib;

import glui.space;
import glui.style;

@safe:

/// Make a new vertical frame
GluiFrame vframe(T...)(T args) {

    return new GluiFrame(args);

}

/// Make a new horizontal frame
GluiFrame hframe(T...)(T args) {

    auto frame = new GluiFrame(args);
    frame.directionHorizontal = true;

    return frame;

}

/// This is a frame, a stylized container for other nodes.
/// Styles: $(UL
///     $(LI `style` = Default style for this node.)
/// )
class GluiFrame : GluiSpace {

    mixin DefineStyles!("style", q{ Style.init });
    mixin ImplHoveredRect;

    this(T...)(T args) {

        super(args);

    }

    protected override void drawImpl(Rectangle area) {

        const style = pickStyle();
        style.drawBackground(area);

        super.drawImpl(area);

    }

    protected override const(Style) pickStyle() const {

        return style;

    }

}
