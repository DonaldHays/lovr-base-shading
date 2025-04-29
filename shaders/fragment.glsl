uniform sampler shadowSampler;
uniform texture2D shadowTexture;
uniform mat4 lightSpaceMatrix;
uniform BaseShadow shadow;

in vec4 vertexLight;
in float vertexFog;

BaseSurface newBaseSurface() {
    BaseSurface surface;
    surface.color = vec4(0, 0, 0, 1);
    surface.emissive = vec4(0, 0, 0, 1);
    return surface;
}

// BEGIN_SURFACE_SHADER

void baseSurface(inout BaseSurface surface) {
    surface.color = Color * getPixel(ColorTexture, UV);
}

// END_SURFACE_SHADER

/**
 * Returns the opacity of the shadow map, from 0 to 1, at the given shadow
 * coordinate.
 *
 * The opacity is determined by `shadow.fadeEdge`.
 */
float shadowMapEdgeOpacity(vec3 shadowCoord) {
    vec3 edgeDist = min(shadowCoord, 1.0 - shadowCoord);
    float minEdgeDist = min(edgeDist.x, min(edgeDist.y, edgeDist.z));
    float edgeRange = (minEdgeDist - shadow.fadeEdge) * (1 / shadow.fadeEdge);
    return clamp(edgeRange, 0.0, 1.0);
}

vec4 lovrmain() {
    // Calculate base surface information from surface shader
    BaseSurface surface = newBaseSurface();
    baseSurface(surface);

    // Calculate shadow amount, if shadows are enabled
    float shadowAmount = 0;
    if (flag_baseShadow) {
        if (shadow.lightIndex != kShadowIndexDisabled) {
            // Convert world-space fragment position to light-space, then to
            // NDC, and then to shadow map coordinates.
            //
            // shadowCoord is 0-1 in all dimensions. NDC is -1 to 1 in x for y,
            // and 0 to 1 for z, so we only need to adjust the x and y
            // components. We do fiddle with the z component for bias, though.
            vec4 posLightSpace = lightSpaceMatrix * vec4(PositionWorld, 1);
            vec3 posNDC = posLightSpace.xyz / posLightSpace.w;
            vec3 shadowCoord = vec3(
                posNDC.xy * 0.5 + 0.5, posNDC.z - shadow.bias
            );
            
            // Accumulate shadow samples
            const int sampleRange = shadow.sampleRange;
            for (int x = -sampleRange; x <= sampleRange; x++) {
                for (int y = -sampleRange; y <= sampleRange; y++) {
                    shadowAmount += texture(
                        sampler2DShadow(shadowTexture, shadowSampler),
                        shadowCoord + vec3(x, y, 0) * shadow.pcfScale
                    );
                }
            }

            // Normalize samples
            float sampleRangeBase = float(sampleRange * 2 + 1);
            shadowAmount /= sampleRangeBase * sampleRangeBase;
            
            // Fade edges
            float edgeOpacity = shadowMapEdgeOpacity(shadowCoord);
            shadowAmount = 1 + (shadowAmount - 1) * edgeOpacity;
        }
    }

    // Calculate light parameters
    vec4 light = vertexLight;
    vec3 normal = normalize(Normal);
    vec3 viewDir = normalize(CameraPositionWorld - PositionWorld);

    // Accumulate fragment lights
    for (int i = 0; i < kLightCount; i++) {
        if (baseLights.lights[i].mode == kLightModeFragment) {
            vec4 lightSample = getBaseLight(i, PositionWorld, viewDir, normal);

            // Apply shadow map, if it impacts this light specifically.
            //
            // `lightIndex` is 1-based to match Lua, so we subtract 1 here.
            if (flag_baseShadow) {
                if (i == shadow.lightIndex - 1) {
                    lightSample *= shadowAmount;
                }
            }

            light += lightSample;
        }
    }

    // Apply universal shadow opacity
    if (flag_baseShadow) {
        if (shadow.lightIndex == kShadowIndexUniversal) {
            light *= 1 + (shadowAmount - 1) * shadow.universalOpacity;
        }
    }

    // Calculate lit color
    vec4 color = surface.color * light + surface.emissive;

    // Apply fog
    if (flag_baseFog) {
        if (fog.mode != kFogModeInactive) {
            float fogAmount = vertexFog;
            if (fog.type == kFogTypeFragment) {
                fogAmount = getFogAmount(
                    length(CameraPositionWorld - PositionWorld)
                );
            }
            color = mix(fog.color, color, fogAmount);
        }
    }

    return color;
}
