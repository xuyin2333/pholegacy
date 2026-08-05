#if !defined INCLUDE_LIGHTING_LPV_FLOODFILL
#define INCLUDE_LIGHTING_LPV_FLOODFILL

#include "voxelization.glsl"

bool is_emitter(uint block_id) {
    return (32u <= block_id && block_id < 80u)
#ifdef HARDCODED_ORE
        || (97u <= block_id && block_id < 104u)
#endif
#ifdef COLORED_CANDLES
        || (104u <= block_id && block_id < 121u)
#endif
    ;
}

bool is_translucent(uint block_id) { return 80u <= block_id && block_id < 96u; }

vec3 get_emitted_light(uint block_id) {
    if (is_emitter(block_id)) {
        if (32u <= block_id && block_id < 80u) {
            return texelFetch(
                       light_data_sampler,
                       ivec2(int(block_id) - 32, 0),
                       0
                   )
                .rgb;
        }

#ifdef HARDCODED_ORE
        if (97u <= block_id && block_id < 104u) {
            // Glowing ores (inspired by Photon-GAMS: https://github.com/Arona74/Photon-GAMS).
            // floodfill.glsl squares emitted_light before storing, so values
            // here are roughly on the sqrt-energy scale used by light_color[].
            if (block_id == 97u) return vec3(0.85, 0.59, 0.45) * 2.5; // Iron
            if (block_id == 98u) return vec3(0.12, 1.00, 0.35) * 2.5; // Emerald
            if (block_id == 99u) return vec3(1.00, 0.84, 0.20) * 2.5; // Gold
            if (block_id == 100u) return vec3(0.12, 0.18, 0.95) * 2.5; // Lapis
            if (block_id == 101u) return vec3(0.76, 0.86, 0.41) * 2.5; // Copper
            if (block_id == 102u) return vec3(0.25, 0.85, 0.95) * 2.5; // Diamond
            if (block_id == 103u) return vec3(1.00, 0.08, 0.08) * 2.5; // Redstone
        }
#endif

#ifdef COLORED_CANDLES
        if (104u <= block_id && block_id < 121u) {
            // Colored candles (inspired by Photon-GAMS: https://github.com/Arona74/Photon-GAMS).
            // Each dye color maps to its own block_id so the LPV emits the
            // matching color into the voxel volume.
            if (block_id == 104u) return vec3(1.00, 0.12, 0.12) * 3.0; // Red
            if (block_id == 105u) return vec3(1.00, 0.58, 0.12) * 3.0; // Orange
            if (block_id == 106u) return vec3(1.00, 0.90, 0.15) * 3.0; // Yellow
            if (block_id == 107u) return vec3(0.55, 0.35, 0.18) * 3.0; // Brown
            if (block_id == 108u) return vec3(0.10, 1.00, 0.20) * 3.0; // Green
            if (block_id == 109u) return vec3(0.40, 1.00, 0.10) * 3.0; // Lime
            if (block_id == 110u) return vec3(0.10, 0.20, 1.00) * 3.0; // Blue
            if (block_id == 111u) return vec3(0.25, 0.70, 1.00) * 3.0; // Light blue
            if (block_id == 112u) return vec3(0.10, 0.88, 0.90) * 3.0; // Cyan
            if (block_id == 113u) return vec3(0.70, 0.15, 1.00) * 3.0; // Purple
            if (block_id == 114u) return vec3(1.00, 0.15, 0.70) * 3.0; // Magenta
            if (block_id == 115u) return vec3(1.00, 0.55, 0.65) * 3.0; // Pink
            if (block_id == 116u) return vec3(0.15, 0.15, 0.15) * 3.0; // Black
            if (block_id == 117u) return vec3(1.00, 0.90, 0.75) * 3.0; // White
            if (block_id == 118u) return vec3(0.35, 0.35, 0.37) * 3.0; // Gray
            if (block_id == 119u) return vec3(0.70, 0.70, 0.65) * 3.0; // Light gray
            if (block_id == 120u) return vec3(1.00, 0.85, 0.60) * 3.0; // Uncolored
        }
#endif
    }

    return vec3(0.0);
}

vec3 get_tint(uint block_id, bool is_transparent) {
    if (is_translucent(block_id)) {
        return texelFetch(light_data_sampler, ivec2(int(block_id) - 80, 1), 0)
            .rgb;
    } else {
        return vec3(is_transparent);
    }
}

ivec3 clamp_to_voxel_volume(ivec3 pos) {
    return clamp(pos, ivec3(0), voxel_volume_size - 1);
}

vec3 gather_light(sampler3D light_sampler, ivec3 pos) {
    const ivec3[6] face_offsets = ivec3[6](
        ivec3(1, 0, 0),
        ivec3(0, 1, 0),
        ivec3(0, 0, 1),
        ivec3(-1, 0, 0),
        ivec3(0, -1, 0),
        ivec3(0, 0, -1)
    );

    if (clamp_to_voxel_volume(pos) != pos) {
        return vec3(0.0);
    }

    const float center_weight = 1.05;

    return (texelFetch(light_sampler, pos, 0).rgb * center_weight
            + texelFetch(
                  light_sampler,
                  clamp_to_voxel_volume(pos + face_offsets[0]),
                  0
            )
                  .xyz
            + texelFetch(
                  light_sampler,
                  clamp_to_voxel_volume(pos + face_offsets[1]),
                  0
            )
                  .xyz
            + texelFetch(
                  light_sampler,
                  clamp_to_voxel_volume(pos + face_offsets[2]),
                  0
            )
                  .xyz
            + texelFetch(
                  light_sampler,
                  clamp_to_voxel_volume(pos + face_offsets[3]),
                  0
            )
                  .xyz
            + texelFetch(
                  light_sampler,
                  clamp_to_voxel_volume(pos + face_offsets[4]),
                  0
            )
                  .xyz
            + texelFetch(
                  light_sampler,
                  clamp_to_voxel_volume(pos + face_offsets[5]),
                  0
            )
                  .xyz)
        * rcp(7.0 * center_weight);
}

void update_lpv(writeonly image3D light_img, sampler3D light_sampler) {
    vec3 current_center
        = get_voxel_volume_center(gbufferModelViewInverse[2].xyz);
    vec3 previous_center = get_voxel_volume_center(vec3(
        gbufferPreviousModelView[0].z,
        gbufferPreviousModelView[1].z,
        gbufferPreviousModelView[2].z
    ));

    ivec3 pos = ivec3(gl_GlobalInvocationID);
    ivec3 previous_pos = ivec3(
        vec3(pos) - floor(previousCameraPosition) + floor(cameraPosition)
        - current_center + previous_center
    );

    uint block_id = texelFetch(voxel_sampler, pos, 0).x;
    bool transparent = block_id == 0u || block_id >= 128u;
    block_id = block_id & 127;
    vec3 light_avg = gather_light(light_sampler, previous_pos);
    vec3 emitted_light = sqr(get_emitted_light(block_id));
    vec3 tint = sqr(get_tint(block_id, transparent));

    vec3 light = emitted_light + light_avg * tint;

    imageStore(light_img, pos, vec4(light, 0.0));
}

#endif // INCLUDE_LIGHTING_LPV_FLOODFILL
