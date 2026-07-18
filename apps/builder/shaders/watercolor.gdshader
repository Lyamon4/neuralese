shader_type canvas_item;
render_mode unshaded;

// ANIMATION DRIVER
// Keyframe this from 0.0 to 1.0 to grow the fluid.
uniform float u_progress : hint_range(0.0, 1.0) = 0.0;
uniform float u_time_scale = 0.2;

// CHROMATIC PALETTE (Regeneron ISEF-inspired)
group_uniforms colors;
uniform vec4 color_bg : source_color = vec4(0.02, 0.0, 0.03, 1.0);
uniform vec4 color_core : source_color = vec4(0.4, 0.0, 0.2, 1.0);
uniform vec4 color_body : source_color = vec4(0.9, 0.1, 0.4, 1.0);
uniform vec4 color_trans : source_color = vec4(1.0, 0.4, 0.2, 1.0);
uniform vec4 color_edge : source_color = vec4(1.0, 0.8, 0.1, 1.0);

// PRNG
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

// 2D Noise
float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    vec2 u = f*f*(3.0-2.0*f);
    return mix(a, b, u.x) + (c - a)* u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Cascaded FBM
float fbm(vec2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 6; i++) {
        value += amplitude * noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    // 1. Screen coordinates (bottom up)
    vec2 st = UV;
    // Optional: correct aspect ratio if applied to a non-square ColorRect
    // st.x *= RENDER_TARGET_SIZE.x / RENDER_TARGET_SIZE.y;
    
    float t = TIME * u_time_scale;

    // 2. Multi-stage Domain Warping (Capillary tracking)
    vec2 q = vec2(
        fbm(st + vec2(0.0, t * 0.1)),
        fbm(st + vec2(1.0, 1.0))
    );
    
    vec2 r = vec2(
        fbm(st + 1.0 * q + vec2(1.7, 9.2) + 0.15 * t),
        fbm(st + 1.0 * q + vec2(8.3, 2.8) + 0.126 * t)
    );
    
    // Final warped structural noise
    float f = fbm(st + r * 2.0);
    
    // 3. Topology Map
    float gradient = 1.0 - UV.y; // Primary lift direction
    // Elevate center slightly for organic doming
    float center_bias = 1.0 - length(vec2(0.5) - vec2(UV.x, UV.y*0.5)) * 1.5;
    
    float spill_struct = gradient * 1.0 + center_bias * 0.5 + f * 1.5 + q.y * 0.5;
    
    // 4. Fluid Expansion Field
    // Map 0..1 progress to -1.0..5.0 elevation range
    float expansion = u_progress * 5.0 - 0.5;
    float wetness = spill_struct - (4.0 - expansion);
    
    // 5. Chromatic Geography
    float edge = smoothstep(0.0, 0.15, wetness) - smoothstep(0.05, 0.2, wetness);
    float trans_band = smoothstep(0.0, 0.4, wetness) - smoothstep(0.3, 0.7, wetness);
    float inner_wash = smoothstep(0.1, 0.8, wetness);
    float deep_core = smoothstep(0.4, 2.0, wetness);
    
    // 6. Blending (Additive Edge, Subtractive Core)
    vec3 color = color_bg.rgb;
    
    // Glowing/Luminous edges
    color += color_edge.rgb * (edge * 1.8);
    color += color_trans.rgb * (trans_band * 1.2);
    
    // Dense pigment body
    color = mix(color, color_body.rgb, inner_wash);
    color = mix(color, color_core.rgb, deep_core);
    
    // 7. Internal Pigment Pooling & Granulation
    float pool_noise = fbm(st * 4.0 + r + t);
    // Subtractive blend blocks light where pigment is thickest
    color *= 1.0 - (pool_noise * 0.3 * inner_wash);
    
    // Paper Grain
    float grain = random(st * 150.0);
    color += grain * 0.03 * inner_wash;
    
    COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}