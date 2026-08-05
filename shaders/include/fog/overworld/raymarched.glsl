#if !defined INCLUDE_FOG_AIR_FOG_VL
#define INCLUDE_FOG_AIR_FOG_VL

#include "/include/fog/overworld/constants.glsl"
#include "/include/lighting/cloud_shadows.glsl"
#include "/include/lighting/shadows/distortion.glsl"
#include "/include/misc/lod_mod_support.glsl"
#include "/include/sky/atmosphere.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/phase_functions.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"

vec2 air_fog_density(vec3 world_pos) {
    const vec2 mul = -rcp(air_fog_falloff_half_life);
    const vec2 add = -mul * air_fog_falloff_start;

    vec2 density = exp2(min(world_pos.y * mul + add, 0.0));

    // fade away below sea level
    density *= linear_step(air_fog_volume_bottom, SEA_LEVEL, world_pos.y);

#ifdef AIR_FOG_CLOUDY_NOISE
    // 3D worley noise FBM for volumetric fog clumping.
    // Uses a 64x64x64 3D worley noise texture (colortex0) for spatial
    // structure, direct density modulation for visible patches, and
    // lift() sharpening for clean patch boundaries.

    vec3 wind = 0.00015 * vec3(1.0, 0.3, 0.7) * frameTimeCounter;
    vec3 p = world_pos * 0.002 + wind;

    // 3-octave 3D worley FBM with domain warping for turbulent, cloud-like
    // clumping. The low-frequency octave is used to warp the sampling
    // coordinates of the mid/high octaves, producing elongated, flowing
    // fog structures instead of round blobs.
    float worley_0 = texture(colortex0, p).r;
    float worley_1 = texture(colortex0, p * 3.5 + wind * 1.5).r;
    float worley_2 = texture(colortex0, p * 9.0 + wind * 2.8).r;

    // Domain warp: use the lowest-frequency octave to distort the other two.
    // This mimics the advection patterns seen in real low-lying clouds.
    vec3 warp = 0.35 * (worley_0 - 0.5) * vec3(1.0, 0.4, 1.0);
    worley_1 = texture(colortex0, p * 3.5 + wind * 1.5 + warp).r;
    worley_2 = texture(colortex0, p * 9.0 + wind * 2.8 + warp * 2.0).r;

    float worley_fbm = worley_0 * 0.50 + worley_1 * 0.30 + worley_2 * 0.20;

    // Direct density modulation via noise inversion, creating visible
    // thick/thin fog patches. Contrast is amplified so that FBM variations
    // produce a wide dynamic range between thin gaps and dense clumps.
    float noise_mod = sqr(1.0 - worley_fbm);
    noise_mod = noise_mod * 2.5 + 0.15;

    // Uniform base layer: blend a minimum uniform density with the noise-
    // modulated density. This ensures gaps in the clumping retain some
    // atmospheric haze instead of looking completely empty, while the
    // noise-modulated portion maintains the full clump structure.
    density.y = density.y * (0.15 + 0.85 * noise_mod);

    // lift() sharpening: creates cleaner patch boundaries by non-linearly
    // remapping the density curve (cloud-style edge sharpening).
    density.y = lift(max0(density.y), 3.0);

    // Altitude shaping: clumps peak near sea level and fade toward the
    // volume top/bottom, preventing unnatural patches at extreme heights.
    float height_weight
        = smoothstep(air_fog_volume_bottom, SEA_LEVEL, world_pos.y)
        * (1.0
           - smoothstep(SEA_LEVEL + 24.0, air_fog_volume_top, world_pos.y));
    density.y *= 0.1 + 0.9 * height_weight;

#endif

    // Time-of-day density modulation.
    // Physical intuition: daytime solar heating suppresses fog formation,
    // nighttime radiative cooling promotes it, with a small boost around
    // twilight hours when relative humidity typically peaks.
    // Modulation is kept subtle (±~20%) so fog never becomes invisible.
    // Noon stays close to the baseline while morning/evening get a modest
    // boost and deepest night a slightly larger one.
    float time_density_mod = 1.0
        + 0.15 * time_sunrise
        + 0.40 * time_sunset
        + 0.60 * time_midnight;
    density *= time_density_mod;

    return density * (OVERWORLD_FOG_INTENSITY); // doubled from 0.5× → full 1.0×
}

// Fast exp(-x) approximation for x in [0, ~10]
float fast_exp_neg(float x) { return exp2(-1.4426950409 * x); }
vec3 fast_exp_neg(vec3 v) { return exp2(-1.4426950409 * v); }

// Fast density without noise — used for sunlight transmittance raymarch.
// Only computes height-based exponential falloff, skipping the expensive
// FBM + noise. This reduces the per-step cost of the 3-sample sunlight
// raymarch from ~90 noise texture fetches to zero.
vec2 air_fog_density_fast(vec3 world_pos) {
    const vec2 mul = -rcp(air_fog_falloff_half_life);
    const vec2 add = -mul * air_fog_falloff_start;

    vec2 density = exp2(min(world_pos.y * mul + add, 0.0));
    density *= linear_step(air_fog_volume_bottom, SEA_LEVEL, world_pos.y);

    // Match the diurnal modulation of air_fog_density() so the sunlight
    // transmittance raymarch stays consistent with the main raymarch.
    float time_density_mod = 1.0
        + 0.15 * time_sunrise
        + 0.40 * time_sunset
        + 0.60 * time_midnight;
    density *= time_density_mod;

    return density * (OVERWORLD_FOG_INTENSITY);
}

mat2x3 raymarch_air_fog(
    vec3 world_start_pos,
    vec3 world_end_pos,
    bool sky,
    float skylight,
    float dither
) {
    vec3 world_dir = world_end_pos - world_start_pos;

    float length_sq = length_squared(world_dir);
    float norm = inversesqrt(length_sq);
    float ray_length = length_sq * norm;
    world_dir *= norm;

    vec3 shadow_start_pos
        = transform(shadowModelView, world_start_pos - cameraPosition);
    shadow_start_pos = project_ortho(shadowProjection, shadow_start_pos);

    vec3 shadow_dir = mat3(shadowModelView) * world_dir;
    shadow_dir = diagonal(shadowProjection).xyz * shadow_dir;

    float distance_to_lower_plane
        = (air_fog_volume_bottom - eyeAltitude) / world_dir.y;
    float distance_to_upper_plane
        = (air_fog_volume_top - eyeAltitude) / world_dir.y;
    float distance_to_volume_start, distance_to_volume_end;

    if (eyeAltitude < air_fog_volume_bottom) {
        // Below volume
        distance_to_volume_start = distance_to_lower_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? -1.0 : distance_to_upper_plane;
    } else if (eyeAltitude < air_fog_volume_top) {
        // Inside volume
        distance_to_volume_start = 0.0;
        distance_to_volume_end = world_dir.y < 0.0
            ? distance_to_lower_plane
            : distance_to_upper_plane;
    } else {
        // Above volume
        distance_to_volume_start = distance_to_upper_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? distance_to_upper_plane : -1.0;
    }

#ifdef LOD_MOD_ACTIVE
    float fog_end = float(lod_render_distance);
#else
    float fog_end = far;
#endif

    if (distance_to_volume_end < 0.0) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    ray_length = sky ? distance_to_volume_end : ray_length;
    ray_length = clamp(ray_length - distance_to_volume_start, 0.0, fog_end);

    uint step_count = uint(
        float(air_fog_min_step_count) + air_fog_step_count_growth * ray_length
    );
    step_count = min(step_count, air_fog_max_step_count);

    float LoV = dot(world_dir, light_dir);

    float rSteps = rcp(float(step_count));
    float base_step_length = ray_length * rSteps * rSteps;

    vec3 transmittance = vec3(1.0);

    mat2x3 light_sun = mat2x3(0.0); // Rayleigh, mie
    mat2x3 light_sky = mat2x3(0.0); // Rayleigh, mie

    for (int i = 0; i < step_count; ++i) {
        float fi = float(i) + dither;
        float fi_prev = max(fi - 1.0, 0.0);
        float actual_step_length = base_step_length * (sqr(fi) - sqr(fi_prev));
        float current_distance = distance_to_volume_start + base_step_length * sqr(fi);

        vec3 world_pos = world_start_pos + world_dir * current_distance;
        vec3 shadow_pos = shadow_start_pos + shadow_dir * current_distance;

        vec3 shadow_screen_pos = distort_shadow_space(shadow_pos) * 0.5 + 0.5;

#if defined SHADOW && !defined PROGRAM_DEFERRED0
        ivec2 shadow_texel = ivec2(
            shadow_screen_pos.xy * shadowMapResolution * MC_SHADOW_QUALITY
        );

#ifdef AIR_FOG_COLORED_LIGHT_SHAFTS
        float depth0 = texelFetch(shadowtex0, shadow_texel, 0).x;
        float depth1 = texelFetch(shadowtex1, shadow_texel, 0).x;
        vec3 color
            = clamp01(texelFetch(shadowcolor0, shadow_texel, 0).rgb * 4.0);
        float color_weight
            = step(depth0, shadow_screen_pos.z) * step(eps, max_of(color));

        color = color * color_weight + (1.0 - color_weight);

        vec3 shadow = step(shadow_screen_pos.z, depth1) * color;
        shadow = (clamp01(shadow_screen_pos) == shadow_screen_pos)
            ? shadow
            : vec3(1.0);
#else
        float depth1 = texelFetch(shadowtex1, shadow_texel, 0).x;
        float shadow = step(
            float(clamp01(shadow_screen_pos) == shadow_screen_pos)
                * shadow_screen_pos.z,
            depth1
        );
#endif
#else
#define shadow 1.0
#endif

        vec2 density = air_fog_density(world_pos) * actual_step_length;

        if (dot(density, vec2(1.0)) < 1e-6) continue;

        vec3 step_optical_depth
            = fog_params.rayleigh_scattering_coeff * density.x
            + fog_params.mie_extinction_coeff * density.y;
        vec3 step_transmittance = fast_exp_neg(step_optical_depth);
        vec3 step_transmitted_fraction
            = (1.0 - step_transmittance) / max(step_optical_depth, eps);

        // Sunlight transmittance — use fast density (no noise) for the 3-sample
        // raymarch toward the sun. This eliminates ~90 noise texture fetches
        // per fog step while having negligible visual impact since the sunlight
        // transmittance is dominated by the height-based density falloff.
        vec2 optical_depth_sun = vec2(0.0);
        float sun_step = 4.0;
        vec3 light_pos = world_pos;
        for (int j = 0; j < 3; j++) {
            sun_step *= 1.5;
            light_pos += light_dir * sun_step;
            vec2 sun_density = air_fog_density_fast(light_pos);
            optical_depth_sun += sun_density * sun_step;
        }

        vec3 step_optical_depth_sun
            = fog_params.rayleigh_scattering_coeff * optical_depth_sun.x
            + fog_params.mie_extinction_coeff * optical_depth_sun.y;
        vec3 sun_transmittance = fast_exp_neg(step_optical_depth_sun);

        // Multi-scattering approximation for sunlight.
        // Analytic geometric-series approximation of higher-order scattering
        // energy. Each order contributes ~half the previous one and is
        // attenuated by the sun-side optical depth; this captures the
        // intuition that thicker fog produces more multi-scatter glow but
        // also self-absorbs it, without running a per-step phase loop.
        float od_sun_mean = dot(step_optical_depth_sun, vec3(1.0 / 3.0));
        float ms_boost = 1.0
            + 0.40 * fast_exp_neg(0.5 * od_sun_mean)
            + 0.18 * fast_exp_neg(1.0 * od_sun_mean);

        // Powder Effect: stronger scattering toward light direction
        // at density boundaries, producing a soft volumetric glow
        float LoV01 = LoV * 0.5 + 0.5;
        float step_density = dot(step_optical_depth, vec3(1.0 / 3.0));
        float powder = (1.0 - fast_exp_neg(0.5 * step_density)) * (1.0 - LoV01) + LoV01;

        vec3 visible_scattering = step_transmitted_fraction * transmittance * powder;

        light_sun[0] += visible_scattering * density.x * shadow * sun_transmittance * ms_boost;
        light_sun[1] += visible_scattering * density.y * shadow * sun_transmittance * ms_boost;
        light_sky[0] += visible_scattering * density.x;
        light_sky[1] += visible_scattering * density.y;

        transmittance *= step_transmittance;

        if (dot(transmittance, vec3(1.0)) < 1e-3) break;
    }

    light_sun[0] *= fog_params.rayleigh_scattering_coeff;
    light_sun[1] *= fog_params.mie_scattering_coeff;
    light_sky[0] *= fog_params.rayleigh_scattering_coeff;
    light_sky[1] *= fog_params.mie_scattering_coeff;

    if (!sky) {
        // Skylight falloff
        light_sky[0] *= max(skylight, eye_skylight);
        light_sky[1] *= max(skylight, eye_skylight);
    }

    float mie_phase = 0.8 * henyey_greenstein_phase(LoV, 0.88)
        + 0.2 * henyey_greenstein_phase(LoV, -0.2);

    /*
    // Single scattering
    vec3 scattering  = light_color * (light_sun * vec2(isotropic_phase,
    mie_phase)); scattering += ambient_color * (light_sky *
    vec2(isotropic_phase));
    /*/
    // Multiple scattering
    vec3 scattering = vec3(0.0);
    float scatter_amount = 1.5;
    float anisotropy = 1.0;

#if defined PROGRAM_DEFERRED0
    vec3 ambient_color = ambient_color_fog;
#endif

    scattering += 4.0 * light_sky * vec2(isotropic_phase) * ambient_color;

    for (int i = 0; i < 4; ++i) {
        float mie_phase = 0.8 * henyey_greenstein_phase(LoV, 0.88 * anisotropy)
            + 0.2 * henyey_greenstein_phase(LoV, -0.2 * anisotropy);

        scattering += scatter_amount
            * (light_sun * vec2(isotropic_phase, mie_phase)) * light_color
            * (1.0 - 0.9 * rainStrength);

        scatter_amount *= 0.5;
        anisotropy *= 0.7;
    }
    //*/

    scattering *= clamp01(1.0 - blindness - darknessFactor);

    // Artifically brighten fog in the early morning and evening (looks nice)
    float evening_glow
        = 0.75 * linear_step(0.05, 1.0, exp(-300.0 * sqr(sun_dir.y + 0.02)));
    scattering += scattering * evening_glow;

    // Rain color shift: match fog color to gray-blue rain lighting
    const vec3 fog_rain_tint = vec3(0.92, 0.95, 1.0);
    float fog_lum = dot(scattering, vec3(0.2627, 0.6780, 0.0593));
    scattering = mix(scattering, vec3(fog_lum) * fog_rain_tint, rainStrength * 0.80);

    return mat2x3(scattering, transmittance);
}

#endif // INCLUDE_FOG_AIR_FOG_VL
