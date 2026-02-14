# Agent Task 28: Animation Blending Accuracy (frameInfo[4])

## Objective
Implement Phase 241 (animation blending): verify and fix the CPU skinning pipeline to correctly blend up to 4 simultaneous animation channels using `frameInfo[4]` weights and `actionWeight`. This ensures smooth animation transitions (walk→run, idle→fire, etc.).

## Files to Create (EXCLUSIVE)
- `code/godot/godot_anim_blend.cpp` — Animation blending verification + helpers
- `code/godot/godot_anim_blend.h` — Public API

## Context
The engine's entity buffer (`gr_entities[]`) provides per-entity animation state:
```c
typedef struct {
    int frame;          // primary frame index
    float backlerp;     // interpolation between frames (0-1)
    // frameInfo for multi-channel blending:
    struct {
        int index;      // animation frame index
        float time;     // animation time
        float weight;   // blend weight (0-1)
    } frameInfo[4];
    float actionWeight; // transition weight between action/movement
} refEntity_t;
```

The existing `godot_skel_model_accessors.cpp` performs CPU skinning but may not correctly weight all 4 channels.

## Implementation

### 1. Verify current blending
Read `godot_skel_model_accessors.cpp` and audit `Godot_Skel_BuildMeshForEntity()` (or equivalent):
- Are all 4 frameInfo channels being used?
- Is actionWeight applied correctly? (actionWeight blends channel 0+1 vs channel 2+3)
- Are bone transforms correctly weighted: `final_bone = Σ(weight_i × bone_transform_i)`?

### 2. Create blending helper
```cpp
struct AnimBlendInput {
    int frame_indices[4];
    float frame_weights[4];
    float frame_times[4];
    float action_weight;      // blends (ch0+ch1) vs (ch2+ch3)
    int active_channels;      // how many channels have weight > 0
};

// Extract blending input from entity buffer
void Godot_AnimBlend_ExtractFromEntity(int entity_index,
                                       AnimBlendInput *out);

// Compute final bone transforms with proper multi-channel blending
void Godot_AnimBlend_ComputeBones(int tiki_handle,
                                  const AnimBlendInput *input,
                                  float *bone_matrices,  // 4x3 per bone
                                  int max_bones);
```

### 3. Blending algorithm
```
For each bone:
  group_a = lerp(channel[0].bone, channel[1].bone, channel[1].weight)
  group_b = lerp(channel[2].bone, channel[3].bone, channel[3].weight)
  final = lerp(group_a, group_b, actionWeight)
```

### 4. Quaternion interpolation
- Convert each channel's bone rotation to quaternion
- Use `slerp` for rotation blending (not matrix lerp)
- Separate position (lerp) from rotation (slerp) for accuracy

### 5. Validation
- Log bone counts and weight values for first entity each frame (debug only)
- Verify weights sum to ~1.0 per bone
- Handle edge cases: weight=0 channels should be skipped

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 241: Animation Blending ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_skel_model.cpp` / `godot_skel_model_accessors.cpp` (read but don't modify — document fixes needed for Agent 4 code)
