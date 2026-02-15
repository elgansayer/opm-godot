# UI/HUD Rendering Position Fix

## Problem Summary

The in-game HUD and main menu were not rendering in the correct positions. This was caused by two critical issues:

1. **Hardcoded viewport fallback**: The code used a hardcoded 1280×720 fallback when the Control node's size wasn't available, causing incorrect scaling on different window sizes.
2. **Broken mouse coordinate transformation**: Mouse input coordinates were not properly transformed to account for letterbox/pillarbox offsets, making UI interaction unreliable or impossible.

## Root Causes

### Issue 1: Viewport Size Fallback
**Location**: `MoHAARunner.cpp::update_2d_overlay()` (line 2998-3000)

**Before**:
```cpp
Vector2 viewport_size = hud_control->get_size();
if (viewport_size.x < 1.0f || viewport_size.y < 1.0f) {
    viewport_size = Vector2(1280.0f, 720.0f);  // hardcoded fallback
}
```

**Problem**: 
- When the Control node hasn't been laid out yet (first few frames), `get_size()` returns (0,0)
- The hardcoded 1280×720 fallback was incorrect for any other window size
- This caused UI elements to be scaled incorrectly and positioned wrong

### Issue 2: Mouse Coordinate Transformation
**Location**: `MoHAARunner.cpp::_unhandled_input()` (line 4930-4943)

**Before**:
```cpp
// Simple linear scaling - WRONG!
Vector2 pos = motion_event->get_position();
int ex = (int)(pos.x * (float)render_w / vp_size.x);
int ey = (int)(pos.y * (float)render_h / vp_size.y);
```

**Problem**:
- Only applied scale transformation
- **Completely ignored `offset_x` and `offset_y`** (letterbox/pillarbox margins)
- Used wrong coordinates (`render_w/render_h` instead of virtual `vid_w/vid_h`)
- Made UI interaction impossible when window aspect ratio differed from engine's 4:3

## Solution

### Part 1: Proper Viewport Size Query

Implemented a robust fallback chain:

```cpp
Vector2 viewport_size = hud_control->get_size();
if (viewport_size.x < 1.0f || viewport_size.y < 1.0f) {
    // Query actual viewport visible rect
    Rect2 visible_rect = get_viewport()->get_visible_rect();
    viewport_size = visible_rect.size;
    
    // Final fallback: query window size directly
    if (viewport_size.x < 1.0f || viewport_size.y < 1.0f) {
        Vector2i win = DisplayServer::get_singleton()->window_get_size();
        viewport_size = Vector2(win);
    }
}
```

**Benefits**:
- Always uses actual window/viewport size
- Works correctly on any screen resolution
- Handles edge cases (first frame, minimized window, etc.)

### Part 2: Unified Coordinate Transformation

Created shared transformation state and calculation:

**New Member Variables** (MoHAARunner.h):
```cpp
// Viewport coordinate transformation (for HUD rendering and mouse input)
float ui_scale_x = 1.0f;       // Scale from engine 640×480 to viewport
float ui_scale_y = 1.0f;
float ui_offset_x = 0.0f;      // Letterbox/pillarbox offset
float ui_offset_y = 0.0f;
int ui_vid_w = 640;            // Engine virtual resolution width
int ui_vid_h = 480;            // Engine virtual resolution height
void update_ui_transform();    // Calculate ui_scale/offset based on viewport size
```

**Transformation Calculation** (`update_ui_transform()`:
```cpp
// Calculate aspect-ratio-preserving scale with letterbox/pillarbox
float engine_aspect = (float)ui_vid_w / (float)ui_vid_h;  // 640/480 = 1.333
float viewport_aspect = viewport_size.x / viewport_size.y;

if (viewport_aspect > engine_aspect) {
    // Viewport wider → pillarbox (bars on sides)
    ui_scale_y = viewport_size.y / (float)ui_vid_h;
    ui_scale_x = ui_scale_y;  // uniform scaling
    ui_offset_x = (viewport_size.x - (float)ui_vid_w * ui_scale_x) * 0.5f;
    ui_offset_y = 0.0f;
} else {
    // Viewport taller → letterbox (bars top/bottom)
    ui_scale_x = viewport_size.x / (float)ui_vid_w;
    ui_scale_y = ui_scale_x;  // uniform scaling
    ui_offset_x = 0.0f;
    ui_offset_y = (viewport_size.y - (float)ui_vid_h * ui_scale_y) * 0.5f;
}
```

**Forward Transform** (engine 640×480 → viewport, used for rendering):
```cpp
Rect2 rect(ui_offset_x + x * ui_scale_x, 
           ui_offset_y + y * ui_scale_y,
           w * ui_scale_x, 
           h * ui_scale_y);
```

**Inverse Transform** (viewport → engine 640×480, used for mouse input):
```cpp
// Inverse transform: subtract offset, then divide by scale
int ex = (int)((pos.x - ui_offset_x) / ui_scale_x);
int ey = (int)((pos.y - ui_offset_y) / ui_scale_y);

// Clamp to virtual screen bounds
if (ex < 0) ex = 0;
if (ey < 0) ey = 0;
if (ex >= ui_vid_w) ex = ui_vid_w - 1;
if (ey >= ui_vid_h) ey = ui_vid_h - 1;
```

## Mathematical Correctness

The transformation is now **mathematically consistent** between rendering and input:

### Rendering (Forward):
```
viewport_x = ui_offset_x + engine_x * ui_scale_x
viewport_y = ui_offset_y + engine_y * ui_scale_y
```

### Input (Inverse):
```
engine_x = (viewport_x - ui_offset_x) / ui_scale_x
engine_y = (viewport_y - ui_offset_y) / ui_scale_y
```

This ensures:
- UI elements render at the exact position where mouse clicks register
- Letterbox/pillarbox bars correctly exclude UI interaction
- All window sizes and aspect ratios work correctly

## Files Modified

1. **openmohaa/code/godot/MoHAARunner.h**
   - Added UI transformation member variables
   - Added `update_ui_transform()` method declaration

2. **openmohaa/code/godot/MoHAARunner.cpp**
   - Implemented `update_ui_transform()` method
   - Updated `update_2d_overlay()` to call `update_ui_transform()` and use cached values
   - Fixed `_unhandled_input()` mouse coordinate transformation
   - Removed hardcoded 1280×720 fallback
   - Added coordinate clamping for mouse input

## Testing Recommendations

Test the UI/HUD rendering with:

1. **Different window sizes**: 800×600, 1280×720, 1920×1080, 2560×1440
2. **Different aspect ratios**: 4:3, 16:9, 16:10, 21:9 (ultrawide)
3. **Window modes**: Windowed, borderless, fullscreen
4. **Edge cases**: Minimized window, first frame, rapid window resizing

For each test:
- Verify HUD elements appear in correct positions
- Verify menu elements appear in correct positions
- Verify mouse clicks register on visible UI elements
- Verify letterbox/pillarbox bars do not accept clicks

## Related Issues

- Original problem: In-game HUD not rendering correctly
- Original problem: Main menu not rendering correctly
- Root cause: UI elements not rendering in correct positions

## Implementation Notes

- The transformation is calculated **once per frame** in `update_ui_transform()`
- Both rendering and input use the **same cached values** (ui_scale_x/y, ui_offset_x/y)
- This ensures perfect consistency and avoids redundant calculations
- The engine's virtual resolution (640×480) is preserved as the canonical coordinate space
- All MOHAA UI code continues to work with 640×480 coordinates unchanged
