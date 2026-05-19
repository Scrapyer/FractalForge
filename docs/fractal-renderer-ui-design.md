# FractalForge UI Design

## Canva Design

- Title: FractalForge UI/UX Design Specification
- Canva design ID: `DAHKHvqXjRs`
- Edit link: https://www.canva.com/d/l6CAW1aVCufe-YP
- View link: https://www.canva.com/d/GhoY06cw1DxHXv_

This document tracks the selected Canva candidate C as the product UI direction
for FractalForge's generic fractal renderer interface.

## Product Shape

FractalForge should feel like a compact macOS creative tool, not a landing page.
The first screen is the working renderer:

```text
+--------------------------------------------------------------------------------+
| Toolbar: Algorithm | Reset | Save Preset | Export | Performance                |
+--------------------+-----------------------------------------+-----------------+
| Algorithm Library  |                                         | Parameters      |
| - Mandelbrot       |                                         | Viewport        |
| - Julia            |          Metal Fractal Canvas            | Iteration       |
| - Burning Ship     |                                         | Formula         |
| - Newton           |                                         | Color           |
| - Multibrot        |                                         | Render          |
| - Mandelbox        |                                         |                 |
+--------------------+-----------------------------------------+-----------------+
| FPS | Iterations | Precision | GPU Memory | Render Time                         |
+--------------------------------------------------------------------------------+
```

## Main Areas

- Center canvas: large Metal-backed viewport with scroll-to-zoom, drag-to-pan,
  double-click reset, live preview, and deep zoom support.
- Left sidebar: selectable fractal algorithm library.
- Right inspector: context-aware parameter panel for the selected algorithm.
- Top toolbar: global commands and fast algorithm switching.
- Bottom status bar: live rendering and performance metrics.

## Algorithm Library

- Mandelbrot: default complex-plane explorer.
- Julia: parameterized family driven by complex constant `c`.
- Burning Ship: Mandelbrot variant using absolute values.
- Newton: root-finding basin visualization.
- Multibrot: Mandelbrot generalized by exponent/power.
- Mandelbox: later 3D/fractal-folding candidate.

## Parameter Panel

- Viewport: center X/Y, scale, rotation, zoom speed.
- Iteration: max iterations, bailout radius, precision mode.
- Formula Parameters: Julia real/imag constant, Multibrot power, Newton roots.
- Color: palette, contrast, smoothing, exposure, background color.
- Render: resolution scale, anti-aliasing, FPS cap, live preview.

## Component States

- Algorithm row: normal, hover, selected.
- Canvas: idle, rendering, deep zoom, paused.
- Parameter control: normal, focused, disabled, invalid.
- Window: visible, hidden, minimized.
- Toolbar command: normal, hover, pressed, disabled.

## Visual Direction

- Background: near-black app chrome, dark gray panels, high-contrast canvas.
- Accent: system blue for selected controls and active commands.
- Typography: SF Pro style, compact labels, monospaced numbers for metrics.
- Controls: segmented pickers, sliders, steppers, numeric fields, toggles, menus.
- Icons: SF Symbols or lucide-style icons for reset, export, performance, presets.

## Implementation Mapping

- `FractalKind` and `FractalDefinition` should drive sidebar rows and inspector
  visibility.
- `FractalViewport` should own selected algorithm, center, scale, and reset logic.
- `MetalRenderer` should receive all active fractal parameters through uniforms.
- `ContentView` should evolve from the current overlay controls into a stable
  three-pane desktop layout.
- Future algorithm-specific parameters should be added to the definition layer
  first, then surfaced in the inspector.
