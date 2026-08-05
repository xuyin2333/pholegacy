#if !defined INCLUDE_MISC_WATER_NORMAL
#define INCLUDE_MISC_WATER_NORMAL

#include "/include/utility/space_conversion.glsl"

// -------------------------------------------------------------------------
// Rain ripple helpers (inspired by Revelation)
// Hash-based pseudo-random raindrop impact ripples for water surfaces.
// -------------------------------------------------------------------------

float rain_ripple_hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 rain_ripple_hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}

vec2 get_water_ripple(vec2 coord) {
    // Computes the slope (gradient) of concentric raindrop impact ripples.
    // Each grid cell has ~45% chance of spawning a ripple that expands
    // outward over its lifetime. Returns vec2 slope in world XZ space.
    const float cell_density = 3.5;
    const int MAX_RADIUS = 1;
    const float wave_frequency = 28.0;

    vec2 uv = coord * cell_density;
    vec2 p0 = floor(uv);

    vec2 circles = vec2(0.0);

    for (int j = -MAX_RADIUS; j <= MAX_RADIUS; ++j) {
        for (int i = -MAX_RADIUS; i <= MAX_RADIUS; ++i) {
            vec2 pi = p0 + vec2(float(i), float(j));

            float h1 = rain_ripple_hash12(pi);
            if (h1 > 0.55) continue;

            vec2 hsh = rain_ripple_hash22(pi);
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

// -------------------------------------------------------------------------
// Legacy fBM noise waves (ported from photon-legacy)
// Gentle, calm ripples using 3-octave fBM noise with rotating direction.
// Enabled via LEGACY_WAVES define in settings.glsl.
// -------------------------------------------------------------------------

#ifdef LEGACY_WAVES

float legacy_wave_height(vec2 coord, float t, vec2 flow_dir) {
    bool flowing = all(greaterThan(abs(flow_dir), vec2(eps)));
    const float directionalFlowSpeed = 1.5;

    float height = 0.0;
    float amp_sum = 0.0;
    float freq = 0.009;        // match photon-legacy exactly
    float amp = 1.0;
    float angle = 0.2;

    for (int i = 0; i < 3; i++) {
        vec2 dir = flowing ? -flow_dir * directionalFlowSpeed : vec2(cos(angle), sin(angle));
        height += texture(noisetex, coord * freq + 0.0065 * t * exp2(float(i)) * dir).y * amp;
        amp_sum += amp;
        amp *= 0.5;
        freq *= 2.0;
        angle += 2.4;
    }
    return height / amp_sum;
}

#endif

float gerstner_wave(
    vec2 coord,
    vec2 wave_dir,
    float t,
    float noise,
    float wavelength
) {
    // Gerstner wave function from Belmu in #snippets, modified
    const float g = 9.8;

    float k = tau / wavelength;
    float w = sqrt(g * k);

    float x = w * t - k * (dot(wave_dir, coord) + noise);

    return sqr(sin(x) * 0.5 + 0.5);
}

void water_waves_setup(
    bool flowing_water,
    vec2 flow_dir,
    out vec2 wave_dir,
    out mat2 wave_rot,
    out float t
) {
    const float wave_speed_still = 0.5 * WATER_WAVE_SPEED_STILL;
    const float wave_speed_flowing = 0.7 * WATER_WAVE_SPEED_FLOWING;
    const float wave_angle = 30.0 * degree;

    t = (flowing_water ? wave_speed_flowing : wave_speed_still)
        * frameTimeCounter;

    wave_dir
        = flowing_water ? flow_dir : vec2(cos(wave_angle), sin(wave_angle));
    wave_rot = flowing_water
        ? mat2(1.0)
        : mat2(
              cos(golden_angle),
              sin(golden_angle),
              -sin(golden_angle),
              cos(golden_angle)
          );
}

float get_water_height(vec2 coord, vec2 wave_dir, mat2 wave_rot, float t) {
    // Parameters

    // Gerstner waves
    const float wave_frequency = 0.7 * WATER_WAVE_FREQUENCY;
    const float persistence = 0.5 * WATER_WAVE_PERSISTENCE;
    const float lacunarity = 1.7 * WATER_WAVE_LACUNARITY;

    // Noise
    const float noise_frequency = 0.007;
    const float noise_strength = 2.0;

    // Height variation
    const float height_variation_frequency = 0.001;
    const float min_height = 0.4;
    const float height_variation_scale = 2.0;
    const float height_variation_offset = -0.5;
    const float height_variation_scroll_speed = 0.1;

    // Reciprical of sum of amplitudes of all waves
    // This is a geometric series with initial value of 1 and common ratio of
    // `persistence`
    const float amplitude_normalization_factor = (1.0 - persistence)
        / (1.0 - pow(persistence, float(WATER_WAVE_ITERATIONS)));

    // Sample noise textures first (latency hiding)

    float[WATER_WAVE_ITERATIONS] wave_noise;
    vec2 noise_coord = (coord + vec2(0.0, 0.25 * t)) * noise_frequency;
    for (uint i = 0u; i < WATER_WAVE_ITERATIONS; ++i) {
        wave_noise[i] = texture(noisetex, noise_coord).y;
        noise_coord *= 2.5;
    }

#ifdef WATER_WAVES_HEIGHT_VARIATION
    float height_variation_noise
        = texture(
              noisetex,
              (coord + vec2(0.0, height_variation_scroll_speed * t))
                  * height_variation_frequency
        )
              .y;
#endif

    // Calculate wave height

    float height = 0.0;
    float amplitude_sum = 0.0;

    float wave_length = 1.0;
    float amplitude = 1.0;
    float frequency = wave_frequency;

    for (uint i = 0u; i < WATER_WAVE_ITERATIONS; ++i) {
        height += gerstner_wave(
                      coord * frequency,
                      wave_dir,
                      t,
                      wave_noise[i] * noise_strength,
                      wave_length
                  )
            * amplitude;

        amplitude *= persistence;
        frequency *= lacunarity;
        wave_length *= 1.5;

        wave_dir *= wave_rot;
    }

#ifdef WATER_WAVES_HEIGHT_VARIATION
    height *= max(
        min_height,
        height_variation_noise * height_variation_scale
            + height_variation_offset
    );
#endif

    return height * amplitude_normalization_factor;
}

vec3 get_water_normal(
    vec3 world_pos,
    vec3 flat_normal,
    vec2 coord,
    vec2 flow_dir,
    float skylight,
    bool flowing_water
) {
    vec2 wave_dir;
    mat2 wave_rot;
    float t;
    water_waves_setup(flowing_water, flow_dir, wave_dir, wave_rot, t);

    const float h = 0.1;
    float wave0 = get_water_height(coord, wave_dir, wave_rot, t);
    float wave1 = get_water_height(coord + vec2(h, 0.0), wave_dir, wave_rot, t);
    float wave2 = get_water_height(coord + vec2(0.0, h), wave_dir, wave_rot, t);

#if defined WORLD_OVERWORLD
    float normal_influence = flowing_water
        ? 0.1
        : mix(0.01, 0.04 + 0.15 * rainStrength, dampen(skylight));
#else
    float normal_influence = 0.04;
#endif
    normal_influence *= smoothstep(
        0.0,
        0.15,
        abs(dot(flat_normal, normalize(world_pos - cameraPosition)))
    ); // prevent noise when looking horizontally
    normal_influence *= WATER_WAVE_STRENGTH;

    vec3 normal;

#ifdef LEGACY_WAVES
    // Photon-legacy fBM noise waves — gentle, calm ripples
    {
        // Y-mixing trick: wave phase varies with water height, avoiding uniform patterns
        vec2 legacy_coord = world_pos.xz - world_pos.y;

        const float legacy_h = 0.1;
        // Use frameTimeCounter directly (legacy uses raw time, not water_waves_setup t)
        float lh0 = legacy_wave_height(legacy_coord, frameTimeCounter, flow_dir);
        float lh_x = legacy_wave_height(legacy_coord + vec2(legacy_h, 0.0), frameTimeCounter, flow_dir);
        float lh_z = legacy_wave_height(legacy_coord + vec2(0.0, legacy_h), frameTimeCounter, flow_dir);

        normal = vec3(lh_x - lh0, lh_z - lh0, legacy_h);

        // Legacy-style normal influence: 0.20 base (legacy=0.15, boosted for
        // photon-main's stronger lighting/SSR flattening)
        float legacy_influence = 0.20 * smoothstep(0.0, 0.05, abs(flat_normal.y));
        legacy_influence *= smoothstep(0.0, 0.1,
            abs(dot(flat_normal, normalize(world_pos - cameraPosition))));
        legacy_influence *= WATER_WAVE_STRENGTH;

        normal.xy *= legacy_influence;
    }
#else
    // Original Gerstner waves
    {
        float wave0 = get_water_height(coord, wave_dir, wave_rot, t);
        float wave1 = get_water_height(
            coord + vec2(h, 0.0), wave_dir, wave_rot, t);
        float wave2 = get_water_height(
            coord + vec2(0.0, h), wave_dir, wave_rot, t);

        normal = vec3(wave1 - wave0, wave2 - wave0, h);
        normal.xy *= normal_influence;
    }
#endif

#if defined WORLD_OVERWORLD
    // Raindrop impact ripples on water surface (inspired by Revelation).
    // Adds concentric expanding ripples on top of existing wave normals.
    if (rainStrength > eps) {
        vec2 ripple_slope = get_water_ripple(world_pos.xz);

        // View-dependent attenuation: ripples vanish at grazing angles
        float view_fade = smoothstep(
            0.0, 0.15,
            abs(dot(flat_normal, normalize(world_pos - cameraPosition)))
        );
        ripple_slope *= 0.10 * view_fade * rainStrength;

        // Build a ripple perturbation vector and blend into the wave normal.
        // `ripple_normal ≈ (slope.x, slope.z, 1.0)` in tangent space,
        // converted to world space via xzy swizzle so XZ slope maps to XZ
        // perturbation and the upward component stays in Y.
        vec3 ripple_normal = normalize(vec3(
            ripple_slope,
            sqrt(max(0.0, 1.0 - dot(ripple_slope, ripple_slope)))
        ));
        ripple_normal = ripple_normal.xzy;

        // Blend: strong blend keeps the wave normal dominant
        // while adding visible ripple rings.
        vec3 ripple_offset = ripple_normal - vec3(0.0, 1.0, 0.0);
        normal = normalize(normal + ripple_offset * 0.4);
    }
#endif

    return normalize(normal);
}

vec2 get_water_parallax_coord(
    vec3 tangent_dir,
    vec2 coord,
    vec2 flow_dir,
    bool flowing_water
) {
    const int step_count = 4;
    const float parallax_depth = 0.2;

    vec2 ray_step = tangent_dir.xy * rcp(-tangent_dir.z) * parallax_depth
        * rcp(float(step_count));

#ifdef LEGACY_WAVES
    float depth_value = legacy_wave_height(coord, frameTimeCounter, flow_dir);
    float depth_march = 0.0;
    float depth_previous;

    while (depth_march < depth_value) {
        coord += ray_step;
        depth_previous = depth_value;
        depth_value = legacy_wave_height(coord, frameTimeCounter, flow_dir);
        depth_march += rcp(float(step_count));
    }
#else
    vec2 wave_dir;
    mat2 wave_rot;
    float t;
    water_waves_setup(flowing_water, flow_dir, wave_dir, wave_rot, t);

    float depth_value = get_water_height(coord, wave_dir, wave_rot, t);
    float depth_march = 0.0;
    float depth_previous;

    while (depth_march < depth_value) {
        coord += ray_step;
        depth_previous = depth_value;
        depth_value = get_water_height(coord, wave_dir, wave_rot, t);
        depth_march += rcp(float(step_count));
    }
#endif

    // Interpolation step

    float depth_before = depth_previous - depth_march + rcp(float(step_count));
    float depth_after = depth_value - depth_march;

    return mix(
        coord,
        coord - ray_step,
        depth_after / (depth_after - depth_before)
    );
}

#endif // INCLUDE_MISC_WATER_NORMAL
