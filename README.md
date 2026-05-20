# FractalForge

FractalForge is a native macOS fractal renderer built with SwiftUI and Metal. It brings together classic complex-plane fractals, 3D distance-field fractals, 4D slice/projection experiments, and several Shadertoy-inspired black hole scenes in one interactive desktop app.

The project is intended as both a visual exploration tool and a shader-porting playground: formulas can be selected from the sidebar, tuned from the inspector, and rendered directly through Metal.

## Highlights

- Native macOS app using SwiftUI, AppKit interop, MetalKit, and custom Metal shaders.
- 2D fractals including Mandelbrot, Julia, Burning Ship, Newton, Multibrot, Mandelbox, Apollonian, value noise, and several Shadertoy-derived scenes.
- 3D and 4D renderers including Mandelbulb, Mandelbox variants, quaternion Julia/Mandelbrot, and 4D lifted versions of selected formulas.
- Black hole renderers with ray marching, relativistic visual effects, accretion disk shading, bloom, temporal feedback, and Shadertoy-style multipass pipelines.
- Ported Shadertoy sources for scenes such as `MdXSzS`, `wXdfzj`, `W3BBzK`, and `3dSyzD`.
- Interactive controls for zooming, panning, camera rotation, ray steps, precision mode, palette, exposure, contrast, resolution scale, antialiasing, and FPS cap.
- Release packaging script that builds the app and creates a zipped `.app` bundle.

## Requirements

- macOS 14.0 or later
- Xcode 16 or later recommended
- Metal-capable Mac

The checked-in Xcode project is `FractalForge.xcodeproj`. The `project.yml` file is also included as project metadata, but XcodeGen is not required for normal builds.

## Build And Run

Run the debug app from the command line:

```bash
./script/build_and_run.sh
```

Useful modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

You can also open `FractalForge.xcodeproj` in Xcode and run the `FractalForge` scheme.

## Package Release

Build a Release app and compress it into a zip archive:

```bash
./script/package_release.sh
```

The package is written to:

```text
build/package/
```

The script accepts environment overrides:

```bash
ARCHIVE_NAME=FractalForge-release OUTPUT_DIR=dist ./script/package_release.sh
```

## Controls

- Mouse drag: pan or rotate, depending on the selected renderer.
- Scroll or trackpad magnify: zoom.
- Double click: reset the current view.
- `W/A/S/D/Q/E/R/F`: camera movement for supported black hole renderers.
- Sidebar: switch between 2D, 3D, 4D, and other renderer groups.
- Inspector: tune formula, camera, precision, color, background, and render settings.

For Shadertoy-style black hole scenes, mouse and keyboard state is converted into shader uniforms and multipass feedback buffers to better match Shadertoy's `iMouse`, keyboard texture, and Buffer A/B/C/D/Image flow.

## Project Layout

```text
FractalForge/
  ContentView.swift          SwiftUI shell, toolbar, sidebar, inspector
  FractalViewport.swift      Render state, fractal catalog, user parameters
  MetalView.swift            MTKView bridge and input handling
  MetalRenderer.swift        Metal render loop and multipass orchestration
  Shaders.metal              Fractal, black hole, bloom, and Shadertoy ports

docs/shadertoy-sources/      Reference GLSL sources used during shader ports
script/build_and_run.sh      Debug build/run helper
script/package_release.sh    Release build and zip packaging helper
scripts/                     Utility scripts
```

## Shadertoy Port Notes

Some scenes are direct algorithmic ports, while others are adapted to fit the app's Metal renderer and shared parameter system. The most complex black hole renderers use explicit multipass textures:

```text
previous BufferA/history + previous BufferB/state
  -> BufferA base render
  -> BufferB bloom mip atlas and state pixels
  -> BufferC horizontal blur
  -> BufferD vertical blur
  -> Image composite
```

The original GLSL references are kept under `docs/shadertoy-sources/` for comparison and future refinement.

## License

No license has been selected yet. Treat the code and shader ports as private unless a license is added.
