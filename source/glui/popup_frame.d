module glui.popup_frame;

import std.traits;
import std.algorithm;

import glui.node;
import glui.tree;
import glui.frame;
import glui.input;
import glui.style;
import glui.utils;
import glui.actions;
import glui.backend;


@safe:


deprecated("popup has been renamed to popupFrame")
alias popup = popupFrame;

deprecated("GluiPopup has been renamed to GluiPopupFrame")
alias GluiPopup = GluiPopupFrame;

alias popupFrame = simpleConstructor!GluiPopupFrame;

/// Spawn a new popup attached to the given tree.
///
/// The popup automatically gains focus.
void spawnPopup(LayoutTree* tree, GluiPopupFrame popup) {

    popup.tree = tree;

    // Set anchor
    popup.anchor = Vector2(
        tree.focusBox.x,
        tree.focusBox.y + tree.focusBox.height
    );

    // Spawn the popup
    tree.queueAction(new PopupNodeAction(popup));
    tree.root.updateSize();

}

/// Spawn a new popup, as a child of another. While the child is active, the parent will also remain so.
///
/// The newly spawned popup automatically gains focus.
void spawnChildPopup(GluiPopupFrame parent, GluiPopupFrame popup) {

    auto tree = parent.tree;

    // Assign the child
    parent.childPopup = popup;

    // Spawn the popup
    spawnPopup(tree, popup);

}

/// This is an override of GluiFrame to simplify creating popups: if clicked outside of it, it will disappear from
/// the node tree.
class GluiPopupFrame : GluiFrame, GluiFocusable {

    mixin defineStyles;
    mixin makeHoverable;
    mixin enableInputActions;

    public {

        /// Position the frame is "anchored" to. A corner of the frame will be chosen to match this position.
        Vector2 anchor;

        /// A child popup will keep this focus alive while focused.
        /// Typically, child popups are spawned as a result of actions within the popup itself, for example in context
        /// menus, an action can spawn a submenu. Use `spawnChildPopup` to spawn child popups.
        GluiPopupFrame childPopup;

        /// Node that had focus before `popupFrame` took over. When the popup is closed using a keyboard shortcut, this
        /// node will take focus again.
        ///
        /// Assigned automatically if `spawnPopup` or `spawnChildPopup` is used, but otherwise not.
        GluiFocusable previousFocus;

    }

    private {

        bool childHasFocus;

    }

    this(NodeParams params, GluiNode[] nodes...) {

        super(params, nodes);

    }

    /// Draw the popup using the assigned anchor position.
    void drawAnchored() {

        const rect = Rectangle(
            anchoredStartCorner.tupleof,
            minSize.tupleof
        );

        // Draw the node within the defined rectangle
        draw(rect);

    }

    private void resizeInternal(LayoutTree* tree, Theme theme, Vector2 space) {

        resize(tree, theme, space);

    }

    /// Get start (top-left) corner of the popup if `drawAnchored` is to be used.
    Vector2 anchoredStartCorner() {

        const viewportSize = io.windowSize;

        // This method is very similar to GluiMapSpace.getStartCorner, but simplified to handle the "automatic" case
        // only.

        // Define important points on the screen: center is our anchor, left is the other corner of the popup if we
        // extend it to the top-left, right is the other corner of the popup if we extend it to the bottom-right
        //  x--|    <- left
        //  |  |
        //  |--o--| <- center (anchor)
        //     |  |
        //     |--x <- right
        const left = anchor - minSize;
        const center = anchor;
        const right = anchor + minSize;

        // Horizontal position
        const x

            // Default to extending towards the bottom-right, unless we overflow
            // |=============|
            // |   ↓ center  |
            // |   O------|  |
            // |   |      |  |
            // |   |      |  |
            // |   |------|  |
            // |=============|
            = right.x < viewportSize.x ? center.x

            // But in case we cannot fit the popup, we might need to reverse the direction
            // |=============|          |=============|
            // |             | ↓ right  | ↓ left
            // |        O------>        | <------O    |
            // |        |      |        | |      |    |
            // |        |      |        | |      |    |
            // |        |------|        | |------|    |
            // |=============|          |=============|
            : left.x >= 0 ? left.x

            // However, if we overflow either way, it's best we center the popup on the screen
            : (viewportSize.x - minSize.x) / 2;

        // Do the same for vertical position
        const y
            = right.y < viewportSize.y ? center.y
            : left.y >= 0 ? left.y
            : (viewportSize.y - minSize.y) / 2;

        return Vector2(x, y);

    }

    protected override void drawImpl(Rectangle outer, Rectangle inner) {

        // Clear directional focus data; give the popup a separate context
        tree.focusDirection = FocusDirection(tree.focusDirection.lastFocusBox);

        super.drawImpl(outer, inner);

        // Forcibly register previous & next focus if missing
        // The popup will register itself just after it gets drawn without this — and it'll be better if it doesn't
        if (tree.focusDirection.previous is null) {

            tree.focusDirection.previous = tree.focusDirection.last;

        }

        if (tree.focusDirection.next is null) {

            tree.focusDirection.next = tree.focusDirection.first;

        }

    }

    protected void mouseImpl() {

    }

    protected bool focusImpl() {

        return false;

    }

    void focus() {

        // Set focus to self
        tree.focus = this;

        // Prefer if children get it, though
        this.focusRecurseChildren();

    }

    /// Give focus to whatever node had focus before this one.
    @(GluiInputAction.cancel)
    void restorePreviousFocus() {

        // Restore focus if possible
        if (previousFocus) {

            previousFocus.focus();

        }

        // Clear focus
        else tree.focus = null;

    }

    bool isFocused() const {

        return childHasFocus
            || tree.focus is this
            || (childPopup && childPopup.isFocused);

    }

}

/// Tree action displaying a popup.
class PopupNodeAction : TreeAction {

    public {

        GluiPopupFrame popup;

    }

    protected {

        /// Safety guard: Do not draw the popup if the tree hasn't resized.
        bool hasResized;

    }

    this(GluiPopupFrame popup) {

        this.startNode = this.popup = popup;
        popup.show();
        popup.toRemove = false;

    }

    override void beforeResize(GluiNode root, Vector2 viewportSize) {

        // Perform the resize
        popup.resizeInternal(root.tree, root.theme, viewportSize);

        // First resize
        if (!hasResized) {

            // Give that popup focus
            popup.previousFocus = root.tree.focus;
            popup.focus();
            hasResized = true;

        }

    }

    /// Tree drawn, draw the popup now.
    override void afterTree() {

        // Don't draw without a resize
        if (!hasResized) return;

        // Stop if the popup requested removal
        if (popup.toRemove) { stop; return; }

        // Draw the popup
        popup.childHasFocus = false;
        popup.drawAnchored();

        // Remove the popup if it has no focus
        if (!popup.isFocused) {
            popup.remove();
            stop;
        }


    }

    override void afterDraw(GluiNode node, Rectangle space) {

        import glui.popup_button;

        // Require at least one resize to search for focus
        if (!hasResized) return;

        // Mark popup buttons
        if (auto button = cast(GluiPopupButton) node) {

            button.parentPopup = popup;

        }

        // Ignore if a focused node has already been found
        if (popup.isFocused) return;

        const focusable = cast(GluiFocusable) node;

        if (focusable && focusable.isFocused) {

            popup.childHasFocus = focusable.isFocused;

        }

    }

    override void afterInput(ref bool keyboardHandled) {

        // Require at least one resize
        if (!hasResized) return;

        // Ignore if input was already handled
        if (keyboardHandled) return;

        // Ignore input in child popups
        if (popup.childPopup && popup.childPopup.isFocused) return;

        // Run actions for the popup
        keyboardHandled = popup.runFocusInputActions;

    }

}
