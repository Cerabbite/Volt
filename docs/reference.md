# Volt Library Reference

## Initialization & Core Functions

### `init-editor`
Initializes the project timeline and renders frames. Must be specified for every project to set up page boundaries and export metadata.

* **`fps`** *(default: 24)* The frames per second of the project.
* **`duration-ms`** *(default: 0)* Duration of the project in milliseconds.
  * `0`: Automatically sets the total duration to the end of the last frame in the registered views.
  * Positive value (e.g., `5000`): Sets total duration strictly to the specified milliseconds.
  * Negative value (e.g., `-1000`): Automatically calculates project duration and adds the absolute value (adds 1 second).

---

### `view`
Registers a sequence to be rendered on the global timeline.

* **`alignment`** *(default: center + horizon)* The default alignment of the sequence content on the stage.
* **`sequence`** The sequence of animated objects or elements to render.
* **`start-frame`** *(default: 0)* The frame index on the global timeline at which the view begins.
* **`duration`** *(default: 0)* Overrides the duration of the sequence:
  * `0`: Uses the sequence's natural ending frame.
  * Positive value: Extends or cuts the view to this exact frame length.
  * Negative value: Extends the view by the absolute value beyond its natural end.

---

### `update`
Updates positional or internal parameters of a Volt object struct/dictionary.

* **`it`**: The Volt object dictionary to modify.
* **`changes`**: Dictionary of parameters to update or insert (e.g., `vmove-x`, `vmove-y`, `vrotate`, `valign`, `vrot-mov-order`, or object-specific arguments).

---

## Media Functions

### `audio`
Schedules an audio track to play on the global media timeline.

* **`input`** Path to the audio file.
* **`start-frame`** *(default: 0)* The frame on the global timeline where the audio begins playing.
* **`cutoff`** *(default: 0)* Frame index at which audio playback is cut off (0 for no cutoff).
* **`volume`** *(default: 1.0)* Multiplier for audio volume level.
* **`fade-out`** *(default: 0)* Number of frames before `cutoff` over which to apply an exponential fade-out filter (`afade`).

---

## Volt Objects

> **Note:** Volt wraps standard Typst objects into dictionary representations so property updates can be applied frame-by-frame. Standard Typst functions remain accessible by prefixing them with `normal-` (e.g., `normal-rect`, `normal-text`, `normal-image`).

### Common Volt Object Attributes
Every Volt object includes these standard transformation properties:
* **`valign`** *(default: top + left)*: Alignment anchor.
* **`vmove-x`** *(default: 0pt)*: Horizontal translation offset.
* **`vmove-y`** *(default: 0pt)*: Vertical translation offset.
* **`vrotate`** *(default: 0deg)*: Rotation angle.
* **`vrot-mov-order`** *(default: "rotate-move")*: Execution order for transformation operations.

---

### `rect`
Constructs a Volt rectangle object wrapper around standard Typst `rect`.

* **`body`** *(default: none)*
* **`fill`** *(default: none)*
* **`height`** *(default: auto)*
* **`width`** *(default: auto)*
* **`inset`** *(default: 0% + 5pt)*
* **`outset`** *(default: (:))*
* **`radius`** *(default: (:))*
* **`stroke`** *(default: auto)*

---

### `image`
Constructs a Volt image object wrapper around standard Typst `image`.

* **`source`**: Image file path.
* **`alt`** *(default: none)*
* **`fit`** *(default: "cover")*
* **`format`** *(default: auto)*
* **`height`** *(default: auto)*
* **`width`** *(default: auto)*
* **`icc`** *(default: auto)*
* **`page`** *(default: 1)*
* **`scaling`** *(default: auto)*

---

### `text`
Constructs a Volt text object with typewriter progress support.

* **`body`**: Content or string to display.
* **`progress`** *(default: 1.0)*: Controls typewriter animation. `0.0` renders no characters; `1.0` renders full text.
* Standard Typst text properties supported: `font`, `fallback`, `style`, `weight`, `stretch`, `size`, `fill`, `stroke`, `tracking`, `spacing`, `baseline`, `overhang`, `top-edge`, `bottom-edge`, `lang`, `region`, `script`, `dir`, `hyphenate`, `costs`, `number-type`, `number-width`, `ligatures`, `discretionary-ligatures`, `historical-ligatures`, `stylistic-set`, `features`, `fractions`, `slashed-zero`, `variations`, `kerning`, `alternates`, `cjk-latin-spacing`.

---

## Animation & Easing Functions

### `interpolation(from-value, to-value, t)`
Linearly interpolates between two values at ratio `t` (`0.0` to `1.0`). Supports `length`, `ratio`, `float`, `int`, `relative`, `angle`, and `color` types.

---

### Easing Generators

#### `cubic-bezier(x1, y1, x2, y2)`
Returns an easing function `t => float` modeled after CSS cubic-bezier curves using Newton-Raphson approximation.

#### `linear(..points)`
Creates a multi-point linear keyframe interpolation function `t => float`. Points can be provided as values or `(value, percentage_time)` tuples.

---

### Predefined Easing Functions
* **`linear-ease`**: `cubic-bezier(0, 0, 1, 1)`
* **`ease-in-out`**: `cubic-bezier(0.42, 0, 0.58, 1)`
* **`ease-in-out-expo`**: `cubic-bezier(0.87, 0, 0.13, 1)`
* **`sudden-start`**: Switches from start value to end value immediately at `t = 0%`.
* **`sudden-middle`**: Switches values at `t = 50%`.
* **`sudden-end`**: Switches values at `t = 100%`.

---

## Python CLI (`volt.py`)

Executes Typst rendering and pipes frame sequences into FFmpeg.

### Usage
```bash
python volt.py <typst_file> [start_sec/end_sec] [--preview]
```

### Flags & Parameters

- [start_sec/end_sec] (optional): Renders a specific slice of the video timeline (e.g., 2/10).
- --preview (optional): Fast preview mode. Uses lower PPI (36), faster NVENC preset (p1), higher CRF (30), and lower render quality. Normal mode uses PPI 72, preset p6, CRF 23.

PPI 144 is 4k quality, 72 1080p, and 36 720p