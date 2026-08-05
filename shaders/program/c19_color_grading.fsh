/*
--------------------------------------------------------------------------------

  Pholegacy by xuyin
  Modified from Photon Shader, original author SixthSurge

  program/c19_color_grading:
  Apply bloom, color grading and tone mapping then convert to rec. 709

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec3 scene_color;

/* RENDERTARGETS: 0 */

in vec2 uv;

#if GRADE_WHITE_BALANCE != 6500
flat in mat3 white_balance_matrix;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // bloom tiles
uniform sampler2D colortex3; // fog transmittance
uniform sampler2D colortex5; // scene color

uniform float aspectRatio;
uniform float blindness;
uniform float darknessFactor;
uniform float frameTimeCounter;

uniform float biome_cave;
uniform float time_noon;
uniform float eye_skylight;
uniform float rainStrength;

uniform vec2 view_pixel_size;

#include "/include/post_processing/tonemap_operators.glsl"
#include "/include/utility/bicubic.glsl"
#include "/include/utility/color.glsl"

vec3 get_bloom() {
    // Upsample last bloom tile. 

    vec2 pad_amount = 6.0 * view_pixel_size;
    vec2 uv_src = clamp(uv, pad_amount, 1.0 - pad_amount) * 0.5;

    return BLOOM_UPSAMPLING_FILTER(colortex0, uv_src).rgb;
}

// Color grading applied before tone mapping
// rgb := color in acescg [0, inf]
vec3 grade_input(vec3 rgb) {
    float brightness = 0.83 * GRADE_BRIGHTNESS;
    float saturation = 0.98 * GRADE_SATURATION;
    saturation = mix(saturation, 0.9, rainStrength);

    // Brightness
    rgb *= brightness;

    // Saturation
    float lum = dot(rgb, luminance_weights);
    rgb = max0(mix(vec3(lum), rgb, saturation));

    // White balance
#if GRADE_WHITE_BALANCE != 6500
    rgb = rgb * rec2020_to_xyz;
    rgb = rgb * white_balance_matrix;
    rgb = rgb * xyz_to_rec2020;
#endif

    rgb = max0(rgb);

    return rgb;
}

// Color grading applied after tone mapping
// rgb := color in linear rec.709 [0, 1]
vec3 grade_output(vec3 rgb) {
    float contrast = GRADE_CONTRAST;

    // Log-space contrast, pivoted around 0.18 (mid-gray linear)
    // contrast = 1.0 → identity; >1 增强对比; <1 降低对比
    rgb = max(rgb, vec3(1e-6));
    vec3 log_rgb = log2(rgb);
    float pivot = log2(0.18);
    log_rgb = pivot + (log_rgb - pivot) * contrast;
    rgb = exp2(log_rgb);

    return clamp01(rgb);
}

float vignette(vec2 uv) {
    const float vignette_size = 16.0;
    const float vignette_intensity = 0.08 * VIGNETTE_INTENSITY;

    float darkness_pulse = 1.0 - dampen(abs(cos(2.0 * frameTimeCounter)));

    float vignette
        = vignette_size * (uv.x * uv.y - uv.x) * (uv.x * uv.y - uv.y);
    vignette = pow(
        vignette,
        vignette_intensity + 0.1 * biome_cave + 0.3 * blindness
            + 0.2 * darkness_pulse * darknessFactor
    );

    return vignette;
}

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    scene_color = texelFetch(colortex5, texel, 0).rgb;

    float exposure = texelFetch(colortex5, ivec2(0), 0).a;

#ifdef BLOOM
    vec3 bloom = get_bloom();
    float bloom_intensity = 0.12 * BLOOM_INTENSITY;

    scene_color = mix(scene_color, bloom, bloom_intensity);

#ifdef BLOOMY_FOG
    vec2 bloomy_data = texture(colortex3, uv * taau_render_scale).rg;

    // Normal bloomy fog: intensity controlled by BLOOMY_FOG_INTENSITY
    scene_color = mix(
        bloom,
        scene_color,
        pow(bloomy_data.x, BLOOMY_FOG_INTENSITY)
    );

#ifdef BLOOMY_RAIN
    // Rain bloom: independent channel, fixed intensity, unaffected by
    // BLOOMY_FOG_INTENSITY
    scene_color = mix(bloom, scene_color, 1.0 - bloomy_data.y);
#endif
#endif
#endif

    scene_color *= exposure;

#ifdef VIGNETTE
    scene_color *= vignette(uv);
#endif

    scene_color = grade_input(scene_color);

#ifdef TONEMAP_COMPARISON
    scene_color
        = uv.x < 0.5 ? tonemap_left(scene_color) : tonemap_right(scene_color);
#else
    scene_color = tonemap(scene_color);
#endif

    scene_color = clamp01(scene_color * working_to_display_color);
    scene_color = grade_output(scene_color);
}
