# GDDrawPlus

GDDrawPlus is a community fork of [GDDraw](https://github.com/ArdonyxApps/GDDraw) by ArdonyxApps, a Godot editor plugin for layered prototype art and multi-object texture painting on 3D surfaces without leaving the editor. Everything GDDraw 0.3.0 does is still here; this fork adds the pieces below. It is not affiliated with or endorsed by the original author.

## What GDDrawPlus adds

- **UV tools.** A UV menu with Auto Unwrap (Smart, Box, Cylinder, Sphere, Planar) and a full UV Editor, so models without UVs can be painted. [UV Tools](addons/GDDrawPlus/docs/uv-tools.md)
- **Paint channels.** Paint emission, roughness, metallic, ambient occlusion, height and normal textures, not only albedo. [Paint Channels](addons/GDDrawPlus/docs/paint-channels.md)
- **Material Brush.** Paint with a PBR material, an ORM material, a texture set from Material Maker or similar, or a baked shader, and paint several channels with one stroke. [Material Brush](addons/GDDrawPlus/docs/material-brush.md)
- **3D workflow fixes.** Open meshes that have no material (including Godot's built-in shapes), scale textures inside a 3D session, faster brushes on 4096x4096 textures, scenes that no longer embed gigabytes of pixels, and keyboard shortcuts that stay out of the way until you click inside GDDraw. [What's New](addons/GDDrawPlus/docs/whats-new.md)

## Requirements

- Godot 4.4 or later, as for GDDraw. GDDrawPlus was developed and tested on **Godot 4.7 and 4.7.2 (.NET)** on Windows. Other versions and operating systems have not been tested.
- A desktop editor build.

## Install

1. Copy the `addons/GDDrawPlus` folder into your project's `addons` folder.
2. If the original GDDraw, or GDDrawPlus 0.3.1, is installed (`addons/GDDraw`), delete that folder first. Both define the same class names, so two copies cannot be enabled together.
3. Enable **GDDrawPlus** in Project > Project Settings > Plugins.
4. Open the **GDDraw** panel at the bottom of the editor. The manual is under **Help > Documentation**.

GDDrawPlus does not update itself (the original updater would replace it with the original GDDraw). To update, download the new release from this repository's Releases page and replace `addons/GDDrawPlus`.

## Documentation

The offline manual is included under **Help > Documentation**; the same Markdown pages render on GitHub:

- [Getting Started](addons/GDDrawPlus/docs/getting-started.md)
- [What's New](addons/GDDrawPlus/docs/whats-new.md)
- [Interface](addons/GDDrawPlus/docs/interface.md)
- [Preferences](addons/GDDrawPlus/docs/preferences.md)
- [Tools](addons/GDDrawPlus/docs/tools.md)
- [Layers](addons/GDDrawPlus/docs/layers.md)
- [2D Drawing](addons/GDDrawPlus/docs/2d-drawing.md)
- [Painting in 3D](addons/GDDrawPlus/docs/3d-painting.md)
- [Paint Channels](addons/GDDrawPlus/docs/paint-channels.md)
- [Material Brush](addons/GDDrawPlus/docs/material-brush.md)
- [UV Tools](addons/GDDrawPlus/docs/uv-tools.md)
- [Saving and Files](addons/GDDrawPlus/docs/saving-and-files.md)
- [Shortcuts](addons/GDDrawPlus/docs/shortcuts.md)
- [Troubleshooting](addons/GDDrawPlus/docs/troubleshooting.md)
- [Known Limitations](addons/GDDrawPlus/docs/known-limitations.md)

## Tests

`test-suite/` holds the automated tests: unit tests, headless editor tests, and a render test that checks channel textures with the real renderer. They run in throwaway projects and never touch yours. See [test-suite/README.md](test-suite/README.md).

## Following the original project

This repository keeps the original history. The `upstream` remote is the original GDDraw and the `upstream-main` branch mirrors its `main`:

    git fetch upstream
    git checkout upstream-main && git merge --ff-only upstream/main
    git checkout main && git merge upstream-main

Most of the additions live in their own folders (`addons/GDDrawPlus/uv`, `addons/GDDrawPlus/material`) and in a limited number of places in `gddraw_dock.gd`, `gddraw_canvas.gd` and the 3D session files, which is where merge conflicts can appear.

## Contributing

Bug reports and pull requests are welcome. Please run the test suite first and mention the Godot version and operating system. Fixes that are not specific to this fork are also worth offering to the original project.

## Credits and licenses

- GDDraw is Copyright (c) 2026 ArdonyxApps, MIT License. Its Lucide icons are under the ISC license.
- The UV editor is derived from Gator Model Studio, Copyright (c) 2026 Blackwater Gator Studios, MIT License.
- Additions in this fork are Copyright (c) 2026 GDDrawPlus contributors, MIT License.

The full texts are in [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).