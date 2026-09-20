# Changelog

## 0.3.1 - GDDraw Plus

First release of the fork, based on GDDraw 0.3.0.

Added
- UV menu with Auto Unwrap and the UV Editor.
- Paint channels: emission, roughness, metallic, ambient occlusion, height, normal.
- Material Brush with material, ORM material, texture set and shader sources, and "Also paint" companion channels.
- Copying of height, occlusion and emission look settings from the brush material to the painted material.
- Creation of a material and texture for meshes that have none, including Godot's built-in shapes.
- Image > Scale Textures in 3D sessions.
- Test suite in `test-suite/`.

Fixed
- Keyboard shortcuts (Ctrl+S and others) no longer act until you have clicked inside GDDraw.
- New textures no longer end up embedded in saved scenes.
- Meshes without UVs no longer throw when opened.
- Built-in shapes (CylinderMesh, SphereMesh, ...) no longer break GDDraw's mesh handling.
- Texture scaling on large layers is fast instead of taking minutes.

Changed
- In-editor self-updating is switched off, because the original updater installs the original GDDraw.