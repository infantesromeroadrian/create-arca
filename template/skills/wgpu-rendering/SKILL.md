---
name: wgpu-rendering
description: >-
  wgpu pipeline setup (device/queue/surface/swapchain), WGSL fundamentals
  (vertex/fragment shaders, bindings, structs), uniform buffer layout
  (std140/std430 alignment, padding), SDF rendering, float precision in
  shaders (f32 ULP, bounded animation clocks, phase accumulation mod 2π),
  glyph atlas and CPU-side text rasterization for GPU upload, damage tracking
  and frame-rate-independent interpolation (1-exp(-dt*k)), Wayland layer-shell
  integration (zwlr_layer_shell_v1, smithay-client-toolkit, raw-window-handle),
  and Vulkan/OpenGL backend selection. Use when building real-time graphics,
  desktop compositors, shader effects, or Wayland wallpapers with wgpu.
paths:
  - "**/*.wgsl"
  - "**/shader*"
  - "**/wgpu*"
  - "**/render*"
  - "**/gpu*"
  - "**/layer_shell*"
  - "**/wayland*"
effort: high
---

# wgpu Rendering — Practical Reference

## 1. Device, Queue, Surface Setup

### Adapter + Device Selection

```rust
use wgpu::{Backends, DeviceDescriptor, Features, InstanceDescriptor, MemoryHints,
           RequestAdapterOptions};

let instance = wgpu::Instance::new(InstanceDescriptor {
    // GL backend (EGL/Wayland): use when Vulkan WSI misbehaves with
    // layer_shell surfaces. Mesa's Vulkan EXT_layer_shell is not
    // universally reliable — GL does the attach+commit dance correctly.
    backends: Backends::GL,   // or Backends::VULKAN | Backends::METAL
    ..Default::default()
});

let adapter = instance
    .request_adapter(&RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: Some(&surface),
        force_fallback_adapter: false,
    })
    .await
    .expect("no adapter found");

// Inherit the adapter's own limits so no feature is silently disabled.
let adapter_limits = adapter.limits();
let (device, queue) = adapter
    .request_device(
        &DeviceDescriptor {
            label: Some("my-device"),
            required_features: Features::empty(),
            required_limits: adapter_limits,
            memory_hints: MemoryHints::Performance,
        },
        None,
    )
    .await
    .expect("device request failed");
```

### Surface Configuration

```rust
use wgpu::{CompositeAlphaMode, PresentMode, SurfaceConfiguration, TextureUsages};

let caps = surface.get_capabilities(&adapter);

// Prefer sRGB — the compositor tone-maps to display gamma correctly.
let format = caps.formats.iter().copied()
    .find(|f| f.is_srgb())
    .unwrap_or(caps.formats[0]);

// Choose Opaque if supported; otherwise take whatever the compositor
// wants. Never hard-code Opaque — it crashes on compositors that
// only expose PreMultiplied.
let alpha_mode = if caps.alpha_modes.contains(&CompositeAlphaMode::Opaque) {
    CompositeAlphaMode::Opaque
} else {
    caps.alpha_modes[0]
};

let config = SurfaceConfiguration {
    usage: TextureUsages::RENDER_ATTACHMENT,
    format,
    width: width.max(1),    // wgpu panics on 0-dimension surfaces
    height: height.max(1),
    present_mode: PresentMode::Fifo,  // Vsync; Immediate for uncapped
    alpha_mode,
    view_formats: vec![],
    desired_maximum_frame_latency: 2,
};
surface.configure(&device, &config);
```

---

## 2. Uniform Buffers — Layout and Alignment

### std140 Rules (what wgpu/WGSL uses for `var<uniform>`)

| WGSL type  | Size  | Alignment | Notes                                 |
|------------|-------|-----------|---------------------------------------|
| `f32`      | 4 B   | 4 B       | —                                     |
| `vec2f`    | 8 B   | 8 B       | —                                     |
| `vec3f`    | 12 B  | **16 B**  | Alignment 16, not 12 — common footgun |
| `vec4f`    | 16 B  | 16 B      | —                                     |
| struct     | —     | 16 B      | Whole struct rounds up to 16 B        |

**Golden rule:** total struct size must be a multiple of 16 B. Add explicit
`_pad` fields in both WGSL and Rust rather than relying on implicit padding —
mismatches are silent GPU UB.

### WGSL Struct (correct)

```wgsl
struct Uniforms {
    resolution: vec2f,   //  8 B @ offset  0
    time:       f32,     //  4 B @ offset  8
    state:      f32,     //  4 B @ offset 12
    amplitude:  f32,     //  4 B @ offset 16
    error:      f32,     //  4 B @ offset 20
    _pad0:      f32,     //  4 B @ offset 24  — explicit, not implicit
    _pad1:      f32,     //  4 B @ offset 28  — total = 32 B, multiple of 16
}

@group(0) @binding(0) var<uniform> u: Uniforms;
```

### Matching Rust Struct

```rust
use bytemuck::{Pod, Zeroable};

#[repr(C)]
#[derive(Copy, Clone, Debug, Pod, Zeroable)]
struct Uniforms {
    resolution: [f32; 2],  //  8 B — matches vec2f
    time:       f32,       //  4 B
    state:      f32,       //  4 B
    amplitude:  f32,       //  4 B
    error:      f32,       //  4 B
    _pad:       [f32; 2],  //  8 B — mirrors _pad0 + _pad1
}
// static_assert: std::mem::size_of::<Uniforms>() == 32
```

Upload on every frame:

```rust
queue.write_buffer(&uniform_buf, 0, bytemuck::bytes_of(&uniforms));
```

### Push Constants (alternative to uniform buffers)

Push constants live in the pipeline layout and skip the staging buffer
entirely — best for data that changes every draw call (per-object transforms).

```rust
// Pipeline layout
let pl = device.create_pipeline_layout(&PipelineLayoutDescriptor {
    label: Some("pl-with-push"),
    bind_group_layouts: &[],
    push_constant_ranges: &[wgpu::PushConstantRange {
        stages: wgpu::ShaderStages::VERTEX | wgpu::ShaderStages::FRAGMENT,
        range: 0..16,  // max 128 B on most hardware; check limits
    }],
});

// In the render pass
pass.set_push_constants(wgpu::ShaderStages::FRAGMENT, 0, bytemuck::bytes_of(&push_data));
```

**When to use push constants vs uniform buffers:**
- Push constants: per-draw, small (≤128 B), changes every frame — avoids buffer staging overhead.
- Uniform buffers: larger or shared across many passes — batched upload with `write_buffer`.

---

## 3. WGSL Fundamentals

### Full-Screen Quad Without a Vertex Buffer

No need for a vertex buffer for a 2D effect. Three vertices generate a
triangle that covers the viewport; the UV coordinates tile into [0,1]².

```wgsl
struct VsOut {
    @builtin(position) position: vec4f,
    @location(0)       uv:       vec2f,
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VsOut {
    var out: VsOut;
    let x = f32((vi << 1u) & 2u);
    let y = f32(vi & 2u);
    out.uv       = vec2f(x, y);
    out.position = vec4f(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    return out;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4f {
    // in.uv is in [0,1]x[0,1]; remap to [-0.5,0.5] for centered SDF work.
    var p = in.uv - vec2f(0.5);
    p.x *= u.resolution.x / max(u.resolution.y, 1.0);  // correct aspect ratio
    // ... render
    return vec4f(color, 1.0);
}
```

### Texture + Sampler Binding

```wgsl
@group(0) @binding(1) var my_tex:  texture_2d<f32>;
@group(0) @binding(2) var my_samp: sampler;

// Usage in fragment shader:
let sample = textureSample(my_tex, my_samp, uv);
```

Bind group layout entry for a filtering sampler:

```rust
BindGroupLayoutEntry {
    binding: 2,
    visibility: ShaderStages::FRAGMENT,
    ty: BindingType::Sampler(SamplerBindingType::Filtering),
    count: None,
}
```

---

## 4. SDF Rendering

Signed distance functions return the signed distance to a shape's boundary:
negative inside, positive outside, zero at the edge.

```wgsl
// Signed distance to a ring centered at the origin.
// Returns negative inside the ring band, positive outside.
fn sd_ring(p: vec2f, radius: f32, thickness: f32) -> f32 {
    return abs(length(p) - radius) - thickness;
}

// Soft anti-aliased edge: map the SDF to [0,1] over a ~2px transition.
let d = sd_ring(p, 0.17, 0.004);
let edge = 1.0 - smoothstep(0.0, 0.002, d);

// Radial glow: Gaussian falloff from the ring boundary.
// width controls the bloom radius.
fn glow(d_abs: f32, width: f32) -> f32 {
    return exp(-d_abs * d_abs / (width * width));
}
let bloom = glow(abs(d), 0.05) * intensity;
```

### Voice-Driven Ring Displacement

Angular displacement of the ring using value noise, driven by audio amplitude:

```wgsl
fn hash21(p: vec2f) -> f32 {
    return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453);
}

fn value_noise(p: vec2f) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);        // smoothstep interpolation
    let a = hash21(i);
    let b = hash21(i + vec2f(1.0, 0.0));
    let c = hash21(i + vec2f(0.0, 1.0));
    let d = hash21(i + vec2f(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Two octaves: base wave (low freq) + detail (high freq). amp=0 collapses
// back to a perfect circle — no discontinuity when audio stops.
fn sd_ring_displaced(p: vec2f, radius: f32, thickness: f32, amp: f32, t: f32) -> f32 {
    let angle     = atan2(p.y, p.x);
    let wave_low  = (value_noise(vec2f(angle * 4.0,  t * 1.2)) - 0.5) * 2.0;
    let wave_high = (value_noise(vec2f(angle * 10.0, t * 2.8)) - 0.5) * 2.0;
    let disp      = (wave_low * 0.7 + wave_high * 0.3) * amp * 0.040;
    return abs(length(p) - (radius + disp)) - thickness;
}
```

---

## 5. Float Precision in Shaders — The Animation Clock Problem

### The Bug: Unbounded f32 Clock

The f32 mantissa has 24 bits. ULP doubles every power of 2. At ~2³⁰ s (~34 years) the
ULP exceeds 1 s, but the problem is visible far earlier: past ~8 M s (~93 days),
ULP exceeds 1 ms — `sin(time*freq)` returns the same value frame to frame for the
breathing pulse, which granulates, then freezes.

**Observed in the ORB project:** real multi-day uptime caused the ring's idle
breathing animation to die.

### The Fix: Bounded Phase Accumulation

Accumulate in f64, wrap to a bounded range before narrowing to f32:

```rust
/// Shader clock period chosen so that wrapping is jump-free at steady state.
///
/// All shader frequency coefficients are multiples of 0.1 (e.g. 1.1, 2.2, 4.5…).
/// PHASE_WRAP = 2*pi*150 ≈ 942.48 s makes WRAP*freq = 2*pi*(150*0.1*n), an exact
/// integer multiple of 2*pi for every steady-state freq.  The wrap is therefore
/// bit-continuous (imperceptible jump < 2e-3 sin-units), while keeping the f32
/// ULP near WRAP at ~6e-5 s — far below any frame dt.
///
/// If you change shader frequency coefficients: re-derive WRAP so that
/// WRAP * each_freq remains an exact integer multiple of 2*pi.
const PHASE_WRAP: f64 = std::f64::consts::TAU * 150.0;

/// Map an unbounded clock (accumulated dt in f64) to the bounded f32 the shader
/// consumes. `rem_euclid` is non-negative and panic-free; the f64→f32 narrowing
/// only happens on the small residual value.
#[inline]
fn bounded_phase(phase_time: f64) -> f32 {
    phase_time.rem_euclid(PHASE_WRAP) as f32
}

// In the render loop:
let dt = now.duration_since(self.last_frame).as_secs_f64();
self.last_frame = now;
self.phase_time += dt;                              // accumulate in f64
self.uniforms.time = bounded_phase(self.phase_time); // narrow to f32 for GPU
```

### Rules

| Situation | Risk | Fix |
|-----------|------|-----|
| `time = elapsed().as_secs_f32()` | ULP death past ~93 days | Accumulate f64, wrap to bounded f32 |
| Unbounded `angle * t` in noise | Slow precision loss | Mod `t` before passing to noise |
| `sin(t * freq)` where freq varies | Wrap jump visible during transition | Accept: ~0.05% frames; bounded residual |
| Phase accumulation reset to 0 | Sudden visual jump | Use `rem_euclid`, not `fmod` |

### Deriving a Jump-Free WRAP

1. Collect every frequency coefficient your shader feeds into `sin()` or passes as a noise time multiplier.
2. Express them as exact fractions over the LCM denominator (e.g. all are multiples of 0.1 → scale by 10).
3. Choose `WRAP = 2*pi * k` where `k` is a positive integer such that `WRAP * f` is an integer multiple of `2*pi` for every `f`.
4. Add unit tests that assert: (a) bounded value stays in `[0, WRAP)` after N years, (b) `sin` advances by a measurable nonzero amount each frame at N years uptime, (c) wrap boundary jump residual < threshold for every steady-state freq.

---

## 6. Frame-Rate-Independent Interpolation

### Per-Frame Lerp (Frame-Rate Coupled — Avoid for Production)

```rust
// [WARN] Rate-coupled: convergence speed changes with frame rate.
// 0.08 at 60 fps ≈ 300 ms to 90%. At 30 fps ≈ 600 ms. At 144 fps ≈ 125 ms.
// Fine for a wallpaper; not fine for gameplay or tight latency targets.
current += (target - current) * 0.08;
```

### Exponential Decay with Real dt (Frame-Rate Independent)

```rust
// [PASS] Rate-independent: convergence is the same regardless of frame rate.
// k = ln(10) / t_90: at k=7.67, reaches 90% in ~300 ms at any fps.
// Formula: weight = 1 - exp(-dt * k)
let k = 7.67_f32;
let weight = 1.0 - (-dt * k).exp();
current += (target - current) * weight;
```

### Common k Values

| Desired t₉₀ | k ≈ ln(10)/t₉₀ | Use case |
|-------------|----------------|----------|
| 50 ms  | 46   | Audio amplitude (lip-sync critical) |
| 120 ms | 19   | Error tint fade |
| 300 ms | 7.7  | Agent state color transition |
| 600 ms | 3.8  | Slow ambient change |

---

## 7. Glyph Atlas / Text Rendering

For GPU text in wgpu: rasterize on the CPU at startup, upload as an
`R8Unorm` texture, sample in the fragment shader.

### CPU Rasterization with `ab_glyph`

```rust
use ab_glyph::{Font, FontRef, PxScale, ScaleFont};

pub struct TextBitmap {
    pub pixels: Vec<u8>,  // R8: one byte per pixel, linear alpha
}

pub fn render(font_bytes: &'static [u8], text: &str, tex_w: u32, tex_h: u32, px: f32)
    -> TextBitmap
{
    let font   = FontRef::try_from_slice(font_bytes).expect("parse font");
    let scale  = PxScale::from(px);
    let scaled = font.as_scaled(scale);

    // Measure total advance for centering (include kerning).
    let mut total_w = 0.0_f32;
    let mut prev: Option<char> = None;
    for ch in text.chars() {
        let g = scaled.scaled_glyph(ch);
        total_w += scaled.h_advance(g.id);
        if let Some(pc) = prev {
            total_w += scaled.kern(font.glyph_id(pc), font.glyph_id(ch));
        }
        prev = Some(ch);
    }

    let ascent   = scaled.ascent();
    let descent  = scaled.descent();
    let x0       = (tex_w as f32 - total_w) * 0.5;
    let baseline = (tex_h as f32 + ascent - descent) * 0.5 - descent;

    let mut pixels = vec![0_u8; (tex_w * tex_h) as usize];
    let mut cursor_x = x0;
    let mut prev_c: Option<char> = None;

    for ch in text.chars() {
        if let Some(pc) = prev_c {
            cursor_x += scaled.kern(font.glyph_id(pc), font.glyph_id(ch));
        }
        let glyph    = scaled.scaled_glyph(ch);
        let advance  = scaled.h_advance(glyph.id);
        let mut placed = scaled.scaled_glyph(ch);
        placed.position = ab_glyph::point(cursor_x, baseline);

        if let Some(outlined) = font.outline_glyph(placed) {
            let bounds = outlined.px_bounds();
            outlined.draw(|gx, gy, v| {
                let px_pos = bounds.min.x as i32 + gx as i32;
                let py_pos = bounds.min.y as i32 + gy as i32;
                if px_pos < 0 || py_pos < 0 { return; }
                let (pxu, pyu) = (px_pos as u32, py_pos as u32);
                if pxu >= tex_w || pyu >= tex_h { return; }
                let idx  = (pyu * tex_w + pxu) as usize;
                let byte = (v.clamp(0.0, 1.0) * 255.0) as u8;
                // Max-blend: multiple glyphs can touch the same pixel
                // (overlapping outlines at small sizes). Keep brightest.
                if byte > pixels[idx] { pixels[idx] = byte; }
            });
        }
        cursor_x += advance;
        prev_c = Some(ch);
    }
    TextBitmap { pixels }
}
```

### Upload to wgpu as R8Unorm

```rust
let text_tex = device.create_texture(&TextureDescriptor {
    label:             Some("text-atlas"),
    size:              Extent3d { width: tex_w, height: tex_h, depth_or_array_layers: 1 },
    mip_level_count:   1,
    sample_count:      1,
    dimension:         TextureDimension::D2,
    format:            TextureFormat::R8Unorm,  // single-channel alpha
    usage:             TextureUsages::TEXTURE_BINDING | TextureUsages::COPY_DST,
    view_formats:      &[],
});
queue.write_texture(
    ImageCopyTexture { texture: &text_tex, mip_level: 0,
                       origin: Origin3d::ZERO, aspect: TextureAspect::All },
    &bitmap.pixels,
    ImageDataLayout { offset: 0, bytes_per_row: Some(tex_w), rows_per_image: Some(tex_h) },
    Extent3d { width: tex_w, height: tex_h, depth_or_array_layers: 1 },
);
```

### Sample in WGSL

```wgsl
@group(0) @binding(1) var text_tex:  texture_2d<f32>;
@group(0) @binding(2) var text_samp: sampler;

// In fragment shader — sample inside bounding box only:
let tuv   = vec2f((p.x + box_w * 0.5) / box_w, (p.y + box_h * 0.5) / box_h);
let alpha = textureSample(text_tex, text_samp, tuv).r;
col       = col + text_color * alpha * text_pulse;
```

---

## 8. Wayland Layer-Shell Integration

### Crates

```toml
[dependencies]
smithay-client-toolkit = { version = "0.19", features = ["xkbcommon"] }
raw-window-handle      = "0.6"
wgpu                   = "23"
```

### zwlr_layer_shell_v1 Concepts

| Field | Value | Effect |
|---|---|---|
| `Layer::Background` | `zwlr_layer_shell_v1.background` | Below all windows — true wallpaper |
| `Layer::Overlay` | `zwlr_layer_shell_v1.overlay` | Above all windows — debug/HUD |
| `Anchor::TOP \| BOTTOM \| LEFT \| RIGHT` | all four edges | Fullscreen stretch |
| `set_exclusive_zone(-1)` | `-1` | No space reserved for panels |
| `KeyboardInteractivity::None` | — | Wallpaper must not steal focus |

### WlHandles Wrapper (wgpu needs `HasDisplayHandle + HasWindowHandle`)

```rust
use raw_window_handle::{
    DisplayHandle, HandleError, HasDisplayHandle, HasWindowHandle,
    RawDisplayHandle, RawWindowHandle, WaylandDisplayHandle, WaylandWindowHandle,
    WindowHandle,
};
use std::ptr::NonNull;

struct WlHandles {
    display: *mut std::ffi::c_void,  // wl_display
    surface: *mut std::ffi::c_void,  // wl_surface
}

// SAFETY: display and surface pointers live for the lifetime of the
// Wayland Connection held in App, which outlives GpuState.
unsafe impl Send for WlHandles {}
unsafe impl Sync for WlHandles {}

impl HasDisplayHandle for WlHandles {
    fn display_handle(&self) -> Result<DisplayHandle<'_>, HandleError> {
        let ptr = NonNull::new(self.display).ok_or(HandleError::Unavailable)?;
        unsafe { Ok(DisplayHandle::borrow_raw(RawDisplayHandle::Wayland(
            WaylandDisplayHandle::new(ptr)
        ))) }
    }
}

impl HasWindowHandle for WlHandles {
    fn window_handle(&self) -> Result<WindowHandle<'_>, HandleError> {
        let ptr = NonNull::new(self.surface).ok_or(HandleError::Unavailable)?;
        unsafe { Ok(WindowHandle::borrow_raw(RawWindowHandle::Wayland(
            WaylandWindowHandle::new(ptr)
        ))) }
    }
}
```

### Extracting Pointers from SCTK

```rust
use smithay_client_toolkit::shell::WaylandSurface;

let display_ptr = conn.backend().display_ptr() as *mut std::ffi::c_void;
let surface_ptr = layer.wl_surface().id().as_ptr() as *mut _ as *mut std::ffi::c_void;

let handles = Arc::new(WlHandles { display: display_ptr, surface: surface_ptr });
let surface = unsafe {
    instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::from_window(handles.as_ref())?)
}?;
```

### Frame Callback (Wayland present discipline)

Register the next frame callback **before** calling `frame.present()`. wgpu
does the `attach + commit` implicitly during `present()`, so there is only one
`wl_surface.commit()` per frame. Registering the callback after present may
miss the first repaint signal.

```rust
// In LayerShellHandler::configure and CompositorHandler::frame:
surface.frame(qh, surface.clone());   // arm next-frame callback
let _ = gpu.render();                  // attach + commit inside present()
```

### Backend Selection: GL vs Vulkan for Layer-Shell

```
GL (EGL/Wayland):
  + Mesa handles the wl_surface attach+commit implicitly
  + Works with all compositors that support zwlr_layer_shell_v1
  - No compute shaders; no storage buffers

Vulkan (Ash):
  + Compute, ray tracing, mesh shaders
  - wgpu's Vulkan WSI path assumes xdg_toplevel handshake;
    zwlr_layer_surface may not send the expected configure sequence
  - On Mesa: VK_KHR_wayland_surface works but zwlr layer positioning
    can be compositor-specific
```

Rule: start with `Backends::GL` for wallpapers and HUDs on Wayland.
Switch to Vulkan only when you need compute or storage — and test across
compositors (Sway, Hyprland, river).

---

## 9. Damage Tracking and Render Gating

When output is mostly static (wallpaper, status bar), skip GPU work until
something actually changes. Save power, reduce thermal noise.

```rust
// Track whether targets have converged to current values.
// Epsilon 1e-3 covers f32 residue from the lerp math.
let state_delta = target_state - current_state;
let amp_delta   = target_amplitude - current_amplitude;
let stable      = state_delta.abs() < 1e-3 && amp_delta.abs() < 1e-3 && already_rendered;

if stable && reduce_motion {
    // Re-arm the Wayland frame callback but skip the wgpu draw.
    // The surface keeps the previous buffer; no flicker.
    return;
}

// Render, then mark stable for next tick.
gpu.render()?;
already_rendered = true;
```

**Invariant:** Reset `already_rendered = false` on every incoming event
(state change, amplitude update, error trigger). This ensures the render
loop fires at least once per change before gating again.

---

## 10. Render Loop Skeleton

```rust
fn render(&mut self) -> Result<(), wgpu::SurfaceError> {
    let frame = self.surface.get_current_texture()?;
    let view  = frame.texture.create_view(&TextureViewDescriptor::default());

    // Advance bounded clock (see §5 — never use unbounded elapsed().as_secs_f32())
    let now = Instant::now();
    let dt  = now.duration_since(self.last_frame).as_secs_f64();
    self.last_frame   = now;
    self.phase_time  += dt;
    self.uniforms.time = bounded_phase(self.phase_time);

    self.uniforms.resolution = [self.config.width as f32, self.config.height as f32];
    self.queue.write_buffer(&self.uniform_buf, 0, bytemuck::bytes_of(&self.uniforms));

    let mut enc = self.device.create_command_encoder(
        &CommandEncoderDescriptor { label: Some("frame-enc") }
    );
    {
        let mut pass = enc.begin_render_pass(&RenderPassDescriptor {
            label: Some("main-pass"),
            color_attachments: &[Some(RenderPassColorAttachment {
                view: &view,
                resolve_target: None,
                ops: Operations {
                    load:  LoadOp::Clear(Color::BLACK),
                    store: StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            occlusion_query_set:      None,
            timestamp_writes:         None,
        });
        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, &self.bind_group, &[]);
        pass.draw(0..3, 0..1);  // fullscreen triangle — no vertex buffer needed
    }

    self.queue.submit(std::iter::once(enc.finish()));
    frame.present();
    Ok(())
}

// Handle surface loss gracefully — do not panic.
match gpu.render() {
    Ok(())                                        => {}
    Err(wgpu::SurfaceError::Lost | wgpu::SurfaceError::Outdated) => {
        gpu.resize(gpu.config.width, gpu.config.height)
    }
    Err(e) => log::warn!("render error: {e:?}"),
}
```

---

## 11. Anti-Patterns

| [FAIL] Don't | [PASS] Do |
|---|---|
| `time = start.elapsed().as_secs_f32()` — ULP death after ~93 days | Accumulate f64 dt, wrap to bounded f32 with `rem_euclid` |
| Uniform struct has `vec3f` with no padding after it | Add explicit `_pad: f32` or use `vec4f`; sizes must be multiples of 16 B |
| `Backends::VULKAN` with `zwlr_layer_surface` on all compositors | Default to `Backends::GL` for layer-shell; document GL limitation |
| Hard-code `CompositeAlphaMode::Opaque` | Query `surface.get_capabilities().alpha_modes`, pick first compatible |
| Register Wayland frame callback **after** `present()` | Register before render — one commit per frame |
| Upload font texture via `write_texture` every frame | Rasterize once at init, upload once, reuse |
| Reset `phase_time = 0` on each resize/reconfigure | Never reset — the wrap mechanism handles long uptime; reset re-introduces the jump |
| Per-frame lerp with constant factor (fps-coupled) | `1 - exp(-dt * k)` for fps-independent convergence speed |
| `width: 0` in `SurfaceConfiguration` | `width.max(1)` — wgpu panics on zero-size surface |
| Rust and WGSL struct layouts differ silently | Mirror every field and padding explicitly in both; `bytemuck::Pod` catches size mismatches at compile time |

---

## 12. Checklist

### Before First Frame

```
□ WGSL uniform struct fields match Rust struct exactly (offsets + padding)
□ SurfaceConfiguration width/height are ≥ 1
□ alpha_mode queried from capabilities — not hard-coded
□ Shader loaded via include_str! (embed at compile time, no runtime path)
□ Bind group layout entries match @group/@binding in WGSL
□ Wayland frame callback registered before first present
□ Using Backends::GL for layer-shell wallpaper
□ Phase accumulator is f64, narrowed to f32 after rem_euclid wrap
```

### Animation

```
□ Clock is bounded — never unbounded elapsed() as f32
□ PHASE_WRAP derived from shader freq coefficients (all multiples of 0.1)
□ Lerp factors use 1-exp(-dt*k) for frame-rate independence (or documented as rate-coupled)
□ Unit tests: pulse still moves at 30/60/365 days uptime
□ Unit tests: wrap boundary residual < 2e-3 for every steady-state freq
```

### Surface Lifecycle

```
□ Resize: update config.width/height and call surface.configure()
□ SurfaceError::Lost / Outdated handled — reconfigure and retry
□ Damage tracking: skip GPU draw when uniforms stable + reduce_motion on
□ already_rendered flag reset on every incoming event
```
