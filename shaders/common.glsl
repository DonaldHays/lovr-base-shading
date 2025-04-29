#define kLightCount 8

#define kLightModeInactive 0
#define kLightModeVertex 1
#define kLightModeFragment 2

#define kFogModeInactive 0
#define kFogModeLinear 1
#define kFogModeExp 2
#define kFogModeExp2 3

#define kFogTypeVertex 0
#define kFogTypeFragment 1

#define kShadowIndexDisabled 0
#define kShadowIndexUniversal -1

layout(constant_id = 900) const bool flag_baseFog = true;
layout(constant_id = 901) const bool flag_baseShadow = true;

struct BaseSurface {
    vec4 color;
    vec4 emissive;
};

struct BaseLight {
    int mode;
    float constantAttenuation;
    float linearAttenuation;
    float quadraticAttenuation;
    float spotCutoff;
    float spotExponent;
    vec3 spotDirection;
    vec4 position;
    vec4 ambient;
    vec4 diffuse;
    vec4 specular;
};

struct BaseLightList {
    BaseLight lights[kLightCount];
};

struct BaseMaterial {
    vec4 ambient;
    vec4 diffuse;
    vec4 emissive;
    vec4 specular;
    float shininess;
};

struct BaseFog {
    int mode;
    int type;
    vec4 color;
    float expDensity;
    float linearStart;
    float linearEnd;
};

struct BaseShadow {
    /**
     * The 1-based index of the light that will use the shadow map. The light
     * must be a fragment light; vertex lights do not support independent
     * shadows.
     *
     * `kShadowIndexDisabled` will disable shadows.
     *
     * `kShadowIndexUniversal` will apply the shadow map to all lights,
     * including vertex lights, adjusted by `universalOpacity`.
     */
    int lightIndex;

    /**
     * The opacity of shadows when `lightIndex` is `kShadowIndexAllLights`.
     */
    float universalOpacity;

    /**
     * The bias to apply to z-axis samples of the shadow map.
     *
     * Raise this value above 0 if you see shadow acne, but try to keep it as
     * low as possible to avoid peter panning.
     *
     * `0.0025` is a decent default.
     */
    float bias;

    /**
     * The spread of PCF samples, when `sampleRange` is greater than 0.
     *
     * Higher values will result in softer shadows, but may produce visible
     * banding. Values should generally be much smaller than `1.0`. For example,
     * even `1.0 / 64.0` is likely to produce banding.
     *
     * `1.0 / 512.0` is a decent default.
     */
    float pcfScale;

    /**
     * A value that controls the number of samples per fragment.
     *
     * The total number of samples will be `(sampleRange * 2 + 1) ^ 2`. e.g:
     * - `0` will result in 1 sample.
     * - `1` will result in 9 samples.
     * - `2` will result in 25 samples.
     *
     * If a value greater than `0` is used, the samples will be spread based on
     * `pcfScale`.
     *
     * Higher values can be used to produce soft shadows, at increasing cost. Be
     * particularly conservative about raising the value above `0` on mobile.
     *
     * This shader uses hardware PCF, so you will receive some softness even if
     * this value is `0`.
     */
    int sampleRange;

    /**
     * The distance from each edge of the shadow map to fade shadows in over,
     * from `0.0` to `0.5`.
     *
     * `0.05` is a decent default for directional lights.
     */
    float fadeEdge;
};

uniform BaseLightList baseLights;
uniform BaseMaterial material;
uniform BaseFog fog;
uniform vec4 ambient;

vec4 getBaseLight(int index, vec3 pos, vec3 viewDir, vec3 normal) {
    BaseLight baseLight = baseLights.lights[index];

    vec3 lightDir;
    float attenuation;

    // Directional lights have a w of 0, point and spotlights have a non-zero w
    if (baseLight.position.w == 0.0) {
        lightDir = normalize(baseLight.position.xyz);
        attenuation = 1.0;
    } else {
        vec3 lightDelta = baseLight.position.xyz / baseLight.position.w - pos;
        float distance = length(lightDelta);
        lightDir = normalize(lightDelta);
        attenuation = 1.0 / (
            baseLight.constantAttenuation +
            baseLight.linearAttenuation * distance +
            baseLight.quadraticAttenuation * distance * distance
        );
    }

    // Ambient
    vec4 ambient = baseLight.ambient * material.ambient;

    // Diffuse
    float diff = max(dot(normal, lightDir), 0.0);
    vec4 diffuse = baseLight.diffuse * diff * material.diffuse;

    // Specular
    vec3 reflectDir = reflect(-lightDir, normal);
    float spec = pow(
        max(dot(viewDir, reflectDir), 0.0),
        max(material.shininess, 0.00001)
    );
    vec4 specular = baseLight.specular * spec * material.specular;

    // Spotlight
    float spot = 1.0f;
    if (baseLight.spotCutoff < 180) {
        float theta = max(
            dot(lightDir, normalize(-baseLight.spotDirection)),
            0.0
        );
        float cutoff = step(cos(radians(baseLight.spotCutoff)), theta);
        spot = pow(theta, baseLight.spotExponent) * cutoff;
    }

    return (ambient + diffuse + specular) * attenuation * spot;
}

float getFogAmount(float distance) {
    if (flag_baseFog) {
        if (fog.mode == kFogModeLinear) {
            return clamp(
                (fog.linearEnd - distance) / (fog.linearEnd - fog.linearStart),
                0.0,
                1.0
            );
        } else if (fog.mode == kFogModeExp) {
            return exp(-fog.expDensity * distance);
        } else if (fog.mode == kFogModeExp2) {
            return exp(-fog.expDensity * distance * distance);
        }
    }

    return 0.0;
}
