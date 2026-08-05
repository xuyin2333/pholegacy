#if !defined INCLUDE_LIGHTING_LPV_LIGHT_COLORS
#define INCLUDE_LIGHTING_LPV_LIGHT_COLORS

const vec3[48] light_color = vec3[48](
    vec3(1.00, 1.00, 1.00) * 12.0, // Strong white light
    vec3(1.00, 1.00, 1.00) * 6.0, // Medium white light
    vec3(1.00, 1.00, 1.00) * 1.0, // Weak white light
    vec3(1.00, 0.55, 0.18) * 14.0, // Strong golden light (kappa: LIGHT_TORCH)
    vec3(1.00, 0.55, 0.18) * 8.0, // Medium golden light (kappa: LIGHT_TORCH)
    vec3(1.00, 0.55, 0.18) * 6.0, // Weak golden light (kappa: LIGHT_TORCH)
    vec3(1.00, 0.30, 0.10) * 5.0, // Redstone components (kappa: LIGHT_REDTORCH)
    vec3(1.00, 0.45, 0.12) * 7.0, // Lava (kappa: LIGHT_FIRE)
    vec3(1.00, 0.45, 0.12) * 9.0, // Medium orange light (kappa: LIGHT_FIRE)
    vec3(1.00, 0.55, 0.18) * 4.0, // Brewing stand (kappa: LIGHT_TORCH)
    vec3(1.00, 0.55, 0.18) * 12.0, // Medium golden light (kappa: LIGHT_TORCH)
    vec3(0.26, 0.42, 1.00) * 6.0, // Soul lights (kappa: LIGHT_SOUL)
    vec3(0.26, 0.42, 1.00) * 14.0, // Beacon (kappa: LIGHT_SOUL)
    vec3(0.75, 1.00, 0.83) * 3.0, // Sculk
    vec3(0.75, 1.00, 0.83) * 1.0, // End portal frame
    vec3(0.76, 0.35, 1.00) * 2.5, // Pink glow (kappa: LIGHT_ENDROD)
    vec3(0.75, 1.00, 0.50) * 1.0, // Sea pickle
    vec3(1.00, 0.55, 0.18) * 4.0, // Nether plants (kappa: LIGHT_TORCH)
    vec3(1.00, 0.55, 0.18) * 8.0, // Candles (kappa: LIGHT_TORCH)
    vec3(1.00, 0.55, 0.18) * 8.0, // Ochre froglight (kappa: LIGHT_TORCH)
    vec3(0.86, 1.00, 0.44) * 8.0, // Verdant froglight
    vec3(0.75, 0.44, 1.00) * 8.0, // Pearlescent froglight
    vec3(0.76, 0.35, 1.00) * 2.0, // Enchanting table (kappa: LIGHT_ENDROD)
    vec3(0.76, 0.35, 1.00) * 4.0, // Amethyst cluster (kappa: LIGHT_ENDROD)
    vec3(0.76, 0.35, 1.00) * 4.0, // Calibrated sculk sensor (kappa: LIGHT_ENDROD)
    vec3(0.75, 1.00, 0.83) * 6.0, // Active sculk sensor
    vec3(1.00, 0.30, 0.10) * 3.3, // Redstone block (kappa: LIGHT_REDTORCH)
    vec3(1.00, 0.55, 0.18) * 3.0, // Open eyeblossom (kappa: LIGHT_TORCH)
    vec3(0.85, 1.3, 1.0) * 3.9, // Copper torch and lanterns
    vec3(1.00, 0.55, 0.18) * 8.0, // Copper Bulbs (kappa: LIGHT_TORCH)
    vec3(0.76, 0.35, 1.00) * 12.0, // Nether portal (kappa: LIGHT_ENDROD)
    vec3(0.0), // End portal
	// Colors for modded light sources (block IDs 64-79)
    vec3(1.00, 1.00, 1.00) * 10.0, // 32 - White       (block 64)
    vec3(0.85, 0.85, 0.85) *  9.0, // 33 - Light Gray  (block 65)
    vec3(0.55, 0.55, 0.55) *  8.0, // 34 - Gray        (block 66)
    vec3(0.20, 0.20, 0.22) *  6.0, // 35 - Black       (block 67)
    vec3(0.55, 0.35, 0.20) *  8.0, // 36 - Brown       (block 68)
    vec3(1.00, 0.10, 0.10) * 10.0, // 37 - Red         (block 69)
    vec3(1.00, 0.45, 0.10) * 10.0, // 38 - Orange      (block 70)
    vec3(1.00, 0.95, 0.20) * 10.0, // 39 - Yellow      (block 71)
    vec3(0.55, 1.00, 0.20) * 10.0, // 40 - Lime        (block 72)
    vec3(0.15, 1.00, 0.20) * 10.0, // 41 - Green       (block 73)
    vec3(0.15, 0.95, 1.00) * 10.0, // 42 - Cyan        (block 74)
    vec3(0.45, 0.75, 1.00) * 10.0, // 43 - Light Blue  (block 75)
    vec3(0.15, 0.30, 1.00) * 10.0, // 44 - Blue        (block 76)
    vec3(0.55, 0.15, 1.00) * 10.0, // 45 - Purple      (block 77)
    vec3(1.00, 0.20, 0.90) * 10.0, // 46 - Magenta     (block 78)
    vec3(1.00, 0.55, 0.85) * 10.0  // 47 - Pink        (block 79)
);

const vec3[16] tint_color = vec3[16](
    vec3(1.0, 0.1, 0.1), // Red
    vec3(1.0, 0.5, 0.1), // Orange
    vec3(1.0, 1.0, 0.1), // Yellow
    vec3(0.7, 0.7, 0.0), // Brown
    vec3(0.1, 1.0, 0.1), // Green
    vec3(0.5, 1.0, 0.5), // Lime
    vec3(0.1, 0.1, 1.0), // Blue
    vec3(0.5, 0.5, 1.0), // Light blue
    vec3(0.1, 1.0, 1.0), // Cyan
    vec3(0.7, 0.1, 1.0), // Purple
    vec3(1.0, 0.1, 1.0), // Magenta
    vec3(1.0, 0.5, 1.0), // Pink
    vec3(0.1, 0.1, 0.1), // Black
    vec3(0.9, 0.9, 0.9), // White
    vec3(0.3, 0.3, 0.3), // Gray
    vec3(0.7, 0.7, 0.7) // Light gray
);

#endif // INCLUDE_LIGHTING_LPV_LIGHT_COLORS
