#if !defined INCLUDE_MISC_RAIN_PUDDLES
#define INCLUDE_MISC_RAIN_PUDDLES

#include "/include/misc/material_masks.glsl"

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float get_flow_height(vec2 coord) {
    const float flow_frequency = 0.3;
    const float flow_speed = 0.15;
    const vec2 flow_dir_0 = vec2(3.0, 4.0) / 5.0;
    const vec2 flow_dir_1 = vec2(-5.0, -12.0) / 13.0;

    float noise_1 =
        texture(
            noisetex,
            coord * flow_frequency +
                frameTimeCounter * flow_speed * flow_dir_0
        )
            .y;
    float noise_2 =
        texture(
            noisetex,
            coord * flow_frequency +
                frameTimeCounter * flow_speed * flow_dir_1
        )
            .y;

    return mix(noise_1, noise_2, 0.5);
}

vec2 get_circular_ripple(vec2 coord) {
    const float cell_density = 4.5;
    const int MAX_RADIUS = 1;
    const float wave_frequency = 28.0;

    vec2 uv = coord * cell_density;
    vec2 p0 = floor(uv);

    vec2 circles = vec2(0.0);

    for (int j = -MAX_RADIUS; j <= MAX_RADIUS; ++j) {
        for (int i = -MAX_RADIUS; i <= MAX_RADIUS; ++i) {
            vec2 pi = p0 + vec2(float(i), float(j));

            float h1 = hash12(pi);
            if (h1 > 0.55) continue;

            vec2 hsh = hash22(pi);
            vec2 p = pi + hsh;

            float speed_var = 0.5 + 0.5 * hsh.y;
            float phase_offset = h1 * 6.28318;

            float raw_t = speed_var * frameTimeCounter + phase_offset;
            float t = fract(raw_t);

            float life_fade = smoothstep(0.0, 0.15, t) * smoothstep(1.0, 0.7, t);

            vec2 v = p - uv;
            float d = length(v) - (float(MAX_RADIUS) + 1.0) * t;

            const float h = 1e-3;
            float d1 = d - h;
            float d2 = d + h;

            float p1 = sin(wave_frequency * d1)
                * smoothstep(-0.8, -0.25, d1)
                * smoothstep(0.05, -0.25, d1);
            float p2 = sin(wave_frequency * d2)
                * smoothstep(-0.8, -0.25, d2)
                * smoothstep(0.05, -0.25, d2);

            circles += 0.5 * normalize(v)
                * ((p2 - p1) / (2.0 * h) * (1.0 - t) * (1.0 - t) * life_fade);
        }
    }

    circles /= float((MAX_RADIUS * 2 + 1) * (MAX_RADIUS * 2 + 1));

    return circles;
}

// 选择垂直表面上的 2D 坐标（沿墙面平面采样）
vec2 get_wall_coord(vec3 world_pos, vec3 flat_normal) {
    vec3 an = abs(flat_normal);
    if (an.x >= an.y && an.x >= an.z) {
        return world_pos.zy;  // 朝 X 的墙
    } else if (an.z >= an.y) {
        return world_pos.xy;  // 朝 Z 的墙
    }
    return world_pos.xz;  // 兜底（水平面）
}

float get_puddle_noise(vec3 world_pos, vec3 flat_normal, vec2 light_levels) {
    const float puddle_frequency = 0.012;

    float puddle = texture(noisetex, world_pos.xz * puddle_frequency).w;

    float wet_factor = cube(wetness);
    puddle -= (1.0 - wet_factor) * 0.55;
    puddle = linear_step(0.15, 0.45, puddle) * biome_may_rain
        * linear_step(0.70, 0.95, flat_normal.y);

    puddle *= (1.0 - cube(light_levels.x))
        * linear_step(14.0 / 15.0, 1.0, light_levels.y);

    return puddle;
}

// 墙面湿润度：垂直表面的湿润强度，含向下流痕调制
// 返回 0-1，0 表示无湿润
float get_wall_wetness(vec3 world_pos, vec3 flat_normal, vec2 light_levels) {
    vec3 an = abs(flat_normal);

    // 仅垂直表面（排除强朝上地面与强朝下天花板）
    float verticality = 1.0 - linear_step(0.3, 0.7, an.y);
    float not_ceiling = linear_step(-0.3, 0.0, flat_normal.y);

    if (verticality < eps || not_ceiling < eps) return 0.0;

    vec2 wall_coord = get_wall_coord(world_pos, flat_normal);

    const float wet_frequency = 0.012;
    float wet_noise = texture(noisetex, wall_coord * wet_frequency).w;

    // 向下流痕：使用 .w 通道（低频 worley），水平/垂直方向均极低频
    // 仅作为大尺度湿润带调制，避免引入小尺度细节导致分布密集
    // wall_coord.y 对应 world Y（向下流），x 方向是墙面水平方向
    float streak = texture(noisetex, vec2(wall_coord.x * 0.015, wall_coord.y * 0.008 + frameTimeCounter * 0.01)).w;
    streak = smoothstep(0.45, 0.70, streak);

    float wet_factor = cube(wetness);

    float wet = wet_noise;
    wet -= (1.0 - wet_factor) * 0.55;
    wet = linear_step(0.15, 0.45, wet);

    // 流痕仅在已湿润区域内做强度调制（不创建新的小斑块）
    wet *= mix(0.75, 1.0, streak);
    wet *= verticality * not_ceiling * biome_may_rain;

    wet *= (1.0 - cube(light_levels.x))
        * linear_step(14.0 / 15.0, 1.0, light_levels.y);

    return clamp01(wet);
}

bool get_rain_puddles(
    vec3 world_pos,
    vec3 flat_normal,
    vec2 light_levels,
    float porosity,
    uint material_mask,
    inout vec3 normal,
    inout vec3 albedo,
    inout vec3 f0,
    inout float roughness,
    inout float ssr_multiplier
) {
#ifndef RAIN_PUDDLES
    return false;
#endif

    const float puddle_f0 = 0.18;
    const float puddle_roughness_min = 0.001;

    if (wetness < eps || biome_may_rain < eps
        || material_mask == MATERIAL_LEAVES) {
        return false;
    }

    float noise_val = get_puddle_noise(world_pos, flat_normal, light_levels);

    if (noise_val < eps * eps) {
        // 地面无积水坑 —— 尝试墙面湿润效果
        float wall_wet = get_wall_wetness(world_pos, flat_normal, light_levels);
        if (wall_wet < eps) return false;

        float wet_strength = wall_wet;
        float damp = 1.0 - porosity * clamp01(wet_strength * 2.0);

        // 湿润外观：变暗、降粗糙度、薄水膜 f0、增强 SSR
        albedo *= mix(1.0, 0.75, wet_strength);
        roughness = mix(roughness, 0.05, damp * wet_strength * 0.85);
        f0 = max(f0, mix(f0, vec3(0.05), wet_strength * 0.55));
        ssr_multiplier = max(ssr_multiplier, wet_strength * 0.6);

        vec2 wall_coord = get_wall_coord(world_pos, flat_normal);
        const float h = 0.1;
        float dh0 = get_flow_height(wall_coord);
        float dhx = get_flow_height(wall_coord + vec2(h, 0.0));
        float dhz = get_flow_height(wall_coord + vec2(0.0, h));

        vec2 drip_grad = (vec2(dhx, dhz) - dh0) / h;
        drip_grad *= 0.006 * wet_strength * rainStrength;

        // 墙面法线扰动：沿 world 水平方向叠加（地面 an.y≈1 时为 0，不影响地面）
        vec3 an = abs(flat_normal);
        vec3 streak_normal = normalize(flat_normal
            + vec3(drip_grad.x, 0.0, drip_grad.y) * 0.5 * (1.0 - an.y));
        normal = normalize(mix(normal, streak_normal, wet_strength * 0.4));

        return true;
    }

    float damp = 1.0 - porosity * clamp01(noise_val * 2.0);
    float puddle_strength = sqrt(noise_val);

    f0 = max(f0, mix(f0, vec3(puddle_f0), puddle_strength));
    roughness = mix(roughness, puddle_roughness_min, damp * puddle_strength);
    ssr_multiplier = max(ssr_multiplier, 1.0 * puddle_strength);

    float puddle_zone = linear_step(0.5, 0.75, noise_val);

    float view_dist = distance(world_pos, cameraPosition);
    float dist_fade = 1.0 - dampen(linear_step(16.0, 64.0, view_dist));

    // --- Flow perturbed flat surface (subtle wobbly flatNormal) ---

    const float h = 0.1;
    float flow_h0 = get_flow_height(world_pos.xz);
    float flow_hx = get_flow_height(world_pos.xz + vec2(h, 0.0));
    float flow_hz = get_flow_height(world_pos.xz + vec2(0.0, h));

    vec2 flow_gradient = (vec2(flow_hx, flow_hz) - flow_h0) / h;
    flow_gradient *= 0.003 * dist_fade * rainStrength;

    vec3 flow_normal = normalize(vec3(-flow_gradient.x, 1.0, -flow_gradient.y));

    vec3 puddle_surface = mix(flat_normal, flow_normal, puddle_zone);

    // --- Circular ripple (only when raining) ---

    vec2 ripple_xy = get_circular_ripple(world_pos.xz);

    ripple_xy
        *= 0.25 * dist_fade
        * smoothstep(
               0.0,
               0.1,
               abs(dot(flat_normal, normalize(world_pos - cameraPosition)))
        );

    vec3 ripple_normal = normalize(
        vec3(ripple_xy, sqrt(max(0.0, 1.0 - dot(ripple_xy, ripple_xy))))
    );
    ripple_normal = ripple_normal.xzy;

    // --- Combine ---

    vec3 puddle_base = mix(normal, puddle_surface, puddle_zone);

    float ripple_weight = puddle_zone * rainStrength * dist_fade;
    vec3 ripple_offset = ripple_normal - vec3(0.0, 1.0, 0.0);
    vec3 final_normal = puddle_base + ripple_offset * ripple_weight;
    normal = normalize_safe(final_normal);

    return true;
}

#endif // INCLUDE_MISC_RAIN_PUDDLES
