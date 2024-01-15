> Warning: The project has been renamed to Fluid and repository has been moved to https://github.com/Samerion/Fluid
>
> It is kept for backwards compatibility, but you are advised to upgrade to the new repository.

<img src="./logo.png" alt="Glui" height="144" align="left" />

A simple and declarative high-level UI library for [Raylib](https://www.raylib.com/) & [Dlang](https://dlang.org/).

It implements a tree node structure, but doesn't provide an event loop and doesn't create a window, making it easier
to integrate in other projects.

Glui has a decent feature set at the moment, but new features will still be added over time. It's mostly stable as of
now and ready to be used, but you may still encounter important changes in minor versions. What Glui is lacking the
most, is decent examples, tutorials and documentation on its design.

## Notes

* Glui currently defaults to bindings for Raylib 3.7.0, if you're using Raylib 4.0 or newer, you should use the
  `raylib4` configuration.
* Glui cannot reliably implement scrolling nodes on macOS.
  * For this reason, those are disabled if using Raylib 3.
  * If you're using Raylib 4 you have to disable them manually using version `Glui_DisableScissors` or you can switch to
    an unstable version of Raylib (`master` branch) which has the issue fixed.
