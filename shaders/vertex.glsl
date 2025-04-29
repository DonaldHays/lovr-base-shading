out vec4 vertexLight;
out float vertexFog;

vec4 lovrmain() {
    // Start with the material emissive color
    vertexLight = material.emissive;

    // Apply ambient
    vertexLight += ambient * material.ambient;

    // Calculate light parameters
    vec3 normal = normalize(Normal);
    vec3 viewDir = normalize(CameraPositionWorld - PositionWorld);
    vec3 worldPos = (WorldFromLocal * VertexPosition).xyz;

    // Accumulate vertex lights
    for (int i = 0; i < kLightCount; i++) {
        if (baseLights.lights[i].mode == kLightModeVertex) {
            vertexLight += getBaseLight(i, worldPos, viewDir, normal);
        }
    }

    // Apply fog
    if (flag_baseFog) {
        if (fog.type == kFogTypeVertex) {
            vertexFog = getFogAmount(length(CameraPositionWorld - worldPos));
        }
    }

    return ClipFromLocal * VertexPosition;
}
