local root = (...):gsub("%.", "/"):gsub("/?init$", "")
local sharedShader = lovr.filesystem.read(root .. "/shaders/common.glsl")

local vertexShader = (
    sharedShader .. lovr.filesystem.read(root .. "/shaders/vertex.glsl")
)

local fragmentShader = (
    sharedShader .. lovr.filesystem.read(root .. "/shaders/fragment.glsl")
)

-- The lights uniform requires the light list to be wrapped in a table. We
-- hide one here so that we don't have to create a new table every time we
-- submit lights.
local lightsUniformContainer = { lights = {} }

--- Creates a shadow map texture and pass for `resolution`.
---
--- This API does not check if the resolution matches any previously existing
--- instance. As an optimization, a client could check if new objects are
--- actually necessary, and not call this function if not.
---
--- @param resolution number
--- @return Texture
--- @return Pass
local function createShadowObjects(resolution)
    local shadowMapTexture = lovr.graphics.newTexture(
        resolution,
        resolution,
        {
            format = "d16",
            linear = false,
            mipmaps = false,
            usage = { "render", "sample" }
        }
    )

    local shadowPass = lovr.graphics.newPass {
        depth = shadowMapTexture, samples = 1
    }
    shadowPass:setClear { depth = 1 }

    return shadowMapTexture, shadowPass
end

--- @class BaseShading
--- @field shadowPass Pass
--- @field private shadowTexture Texture
--- @field private shadowSampler Sampler
--- @field private lightSpaceMatrix any
local BaseShading = {}
BaseShading.__index = BaseShading

--- A type that controls whether and how a light is calculated.
---
--- @enum LightMode
BaseShading.LightMode = {
    --- The light is inactive and will not be used in the shading calculations.
    kInactive = 0,

    --- The light is calculated per-vertex, with the results interpolated across
    --- the surface of the object.
    kVertex = 1,

    --- The light is calculated per-fragment, which is more accurate but slower.
    kFragment = 2,
}

--- A type that controls whether fog is enabled, and, if so, its primary
--- equation.
---
--- @enum FogMode
BaseShading.FogMode = {
    --- Fog is disabled.
    kInactive = 0,

    --- Fog is calculated using a linear equation.
    kLinear = 1,

    --- Fog is calculated using an exponential equation.
    kExp = 2,

    --- Fog is calculated using an exponential equation with a squared distance.
    kExp2 = 3,
}

--- A type that controls whether fog is calculated per-vertex or per-fragment.
---
--- @enum FogType
BaseShading.FogType = {
    --- Fog is calculated per-vertex, with the results interpolated across the
    --- surface of the object.
    kVertex = 0,

    --- Fog is calculated per-fragment, which is more accurate but slower.
    kFragment = 1,
}

--- Sentinel values that signal either that shadows are disabled, or that all
--- lights should be darkened by the shadow map.
BaseShading.ShadowLightIndex = {
    --- Don't use the shadow map.
    kDisabled = 0,

    --- Use the shadow map to darken all lights. The opacity of the shadow
    --- will be based on the `universalOpacity` field of the `BaseShadow`.
    kUniversal = -1,
}

--- Returns a new light, preconfigured with the values in `props`.
---
--- If any `BaseLight` keys are missing from `props`, they will be filled with
--- the following defaults:
---
--- - `mode`: `BaseShading.LightMode.kInactive`
--- - `constantAttenuation`: `1`
--- - `linearAttenuation`: `0`
--- - `quadraticAttenuation`: `0`
--- - `spotCutoff`: `180`
--- - `spotExponent`: `0`
--- - `spotDirection`: `{ 0, 0, -1 }`
--- - `position`: `{ 0, 0, 1, 0 }`
--- - `ambient`: `{ 0, 0, 0, 1 }`
--- - `diffuse`: `{ 0, 0, 0, 1 }`
--- - `specular`: `{ 0, 0, 0, 1 }`
---
--- @param props? BaseLight
--- @return BaseLight
function BaseShading.newLight(props)
    props = props or {}

    return {
        mode = props.mode or BaseShading.LightMode.kInactive,
        constantAttenuation = props.constantAttenuation or 1,
        linearAttenuation = props.linearAttenuation or 0,
        quadraticAttenuation = props.quadraticAttenuation or 0,
        spotCutoff = props.spotCutoff or 180,
        spotExponent = props.spotExponent or 0,
        spotDirection = props.spotDirection or lovr.math.newVec3(0, 0, -1),
        position = props.position or lovr.math.newVec4(0, 0, 1, 0),
        ambient = props.ambient or lovr.math.newVec4(0, 0, 0, 1),
        diffuse = props.diffuse or lovr.math.newVec4(0, 0, 0, 1),
        specular = props.specular or lovr.math.newVec4(0, 0, 0, 1),
    }
end

--- Returns a new material, preconfigured with the values in `props`.
---
--- If any `BaseMaterial` keys are missing from `props`, they will be filled
--- with the following defaults:
---
--- - `ambient`: `{ 0.2, 0.2, 0.2, 1 }`
--- - `diffuse`: `{ 0.8, 0.8, 0.8, 1 }`
--- - `emissive`: `{ 0, 0, 0, 1 }`
--- - `specular`: `{ 0, 0, 0, 1 }`
--- - `shininess`: `0`
---
--- @param props? BaseMaterial
--- @return BaseMaterial
function BaseShading.newMaterial(props)
    props = props or {}

    return {
        ambient = props.ambient or lovr.math.newVec4(0.2, 0.2, 0.2, 1),
        diffuse = props.diffuse or lovr.math.newVec4(0.8, 0.8, 0.8, 1),
        emissive = props.emissive or lovr.math.newVec4(0, 0, 0, 1),
        specular = props.specular or lovr.math.newVec4(0, 0, 0, 1),
        shininess = props.shininess or 0,
    }
end

--- Returns a new fog configuration, preconfigured with the values in `props`.
---
--- If any `BaseFog` keys are missing from `props`, they will be filled with the
--- following defaults:
---
--- - `mode`: `BaseShading.FogMode.kInactive`
--- - `type`: `BaseShading.FogType.kVertex`
--- - `color`: `{ 0, 0, 0, 1 }`
--- - `expDensity`: `1`
--- - `linearStart`: `0`
--- - `linearEnd`: `1`
---
--- @param props? BaseFog
--- @return BaseFog
function BaseShading.newFog(props)
    props = props or {}

    return {
        mode = props.mode or BaseShading.FogMode.kInactive,
        type = props.type or BaseShading.FogType.kVertex,
        color = props.color or lovr.math.newVec4(0, 0, 0, 1),
        expDensity = props.expDensity or 1,
        linearStart = props.linearStart or 0,
        linearEnd = props.linearEnd or 1,
    }
end

--- Returns a new shadow configuration, preconfigured with the values in
--- `props`.
---
--- If any `BaseShadow` keys are missing from `props`, they will be filled with
--- the following defaults:
---
--- - `lightIndex`: `BaseShading.ShadowLightIndex.kDisabled`
--- - `universalOpacity`: `0.5`
--- - `bias`: `0.0025`
--- - `pcfScale`: `1.0 / 512.0`
--- - `sampleRange`: `0`
--- - `fadeEdge`: `0`
---
--- @param props? BaseShadow
--- @return BaseShadow
function BaseShading.newShadow(props)
    props = props or {}

    return {
        lightIndex = props.lightIndex or BaseShading.ShadowLightIndex.kDisabled,
        universalOpacity = props.universalOpacity or 0.5,
        bias = props.bias or 0.0025,
        pcfScale = props.pcfScale or (1.0 / 512.0),
        sampleRange = props.sampleRange or 0,
        fadeEdge = props.fadeEdge or 0,
    }
end

--- A material that does not visually respond to lighting, instead using an
--- emissive color to render a fullbright appearance.
---
--- @type BaseMaterial
BaseShading.unlitMaterial = BaseShading.newMaterial {
    ambient = lovr.math.newVec4(0, 0, 0, 1),
    diffuse = lovr.math.newVec4(0, 0, 0, 1),
    emissive = lovr.math.newVec4(1, 1, 1, 1),
}

--- A default fog configuration that disables fog.
---
--- @type BaseFog
BaseShading.noFog = BaseShading.newFog {}

--- Creates a new `BaseShading` instance.
---
--- You can use a `BaseShading` object to create surface shaders, and send
--- parameters when a surface shader is bound.
---
--- The `config` is optional. If `config` is not provided, or any of the
--- following keys are not provided, the following defaults are used:
---
--- - `shadowResolution`: `512`
---
--- @param config? BaseConfig
--- @return BaseShading
function BaseShading:new(config)
    config = config or {}

    local instance = {}
    setmetatable(instance, self)

    local shadowResolution = config.shadowResolution or 512
    local shadowMapTexture, shadowPass = createShadowObjects(shadowResolution)

    local shadowSampler = lovr.graphics.newSampler {
        wrap = { "clamp", "clamp", "clamp" },
        compare = "less",
        usage = { "render", "sample" }
    }

    instance.shadowPass = shadowPass
    instance.shadowTexture = shadowMapTexture
    instance.shadowSampler = shadowSampler
    instance.lightSpaceMatrix = lovr.math.newMat4()

    return instance
end

--- Returns a new surface shader built from `source`.
---
--- If `source` is not provided, a default surface shader is created.
---
--- Surface shaders define the appearance of the surface of an object. Their
--- output is used by the light and shadow model to determine the final color of
--- a fragment.
---
--- A surface shader must implement a function with the following signature:
---
--- ```glsl
--- void baseSurface(inout BaseSurface surface)
--- ```
---
--- The `BaseSurface` struct is defined as follows:
---
--- ```glsl
--- struct BaseSurface {
---    vec4 color;
---    vec4 emissive;
--- };
--- ```
---
--- The `baseSurface` function should write to the `color` and, optionally,
--- `emissive` fields.
---
--- The `flags` table contains shader flags. The base shading library defines
--- the following flags:
---
--- - `baseFog`: If `false`, fog will not be rendered, regardless of the
---   `BaseFog` configuration. Default: `true`.
--- - `baseShadow`: If `false`, shadows will not be rendered, regardless of the
---   `BaseShadow` configuration. Default: `true`.
---
--- @param source? string
--- @param flags? table
--- @return Shader
function BaseShading:newSurfaceShader(source, flags)
    local options = {
        flags = flags or {}
    }

    if source then
        local substituted = string.gsub(
            fragmentShader,
            "// BEGIN_SURFACE_SHADER\n.*// END_SURFACE_SHADER\n",
            source
        )

        return lovr.graphics.newShader(vertexShader, substituted, options)
    else
        return lovr.graphics.newShader(vertexShader, fragmentShader, options)
    end
end

--- Changes the resolution of the shadow map texture to `resolution`.
---
--- This API creates a new shadow pass, therefore it should not be called while
--- the existing shadow pass is in use.
function BaseShading:setShadowResolution(resolution)
    -- Don't generate new objects if the resolution is the same
    if resolution == self.shadowTexture:getWidth() then
        return
    end

    local shadowMapTexture, shadowPass = createShadowObjects(resolution)

    self.shadowTexture = shadowMapTexture
    self.shadowPass = shadowPass
end

--- Sends `lights` to the current shader of `pass`.
---
--- The current shader must be a surface shader.
---
--- @param pass Pass
--- @param lights BaseLight[]
function BaseShading:sendLights(pass, lights)
    lightsUniformContainer.lights = lights
    pass:send("BaseLights", lightsUniformContainer)
end

--- Sends `material` to the current shader of `pass`.
---
--- The current shader must be a surface shader.
---
--- @param pass Pass
--- @param material BaseMaterial
function BaseShading:sendMaterial(pass, material)
    pass:send("material", material)
end

--- Sends `fog` to the current shader of `pass`.
---
--- The current shader must be a surface shader.
---
--- @param pass Pass
--- @param fog BaseFog
function BaseShading:sendFog(pass, fog)
    pass:send("fog", fog)
end

--- Sends `ambient` to the current shader of `pass`.
---
--- The current shader must be a surface shader.
---
--- @param pass Pass
--- @param ambient Vec4
function BaseShading:sendAmbient(pass, ambient)
    pass:send("ambient", ambient)
end

--- Sends `shadow` to the current shader of `pass`.
---
--- The current shader must be a surface shader.
---
--- @param pass Pass
--- @param shadow BaseShadow
function BaseShading:sendShadow(pass, shadow)
    pass:send("shadowSampler", self.shadowSampler)
    pass:send("shadowTexture", self.shadowTexture)
    pass:send("lightSpaceMatrix", self.lightSpaceMatrix)
    pass:send("shadow", shadow)
end

--- Resets the shadow pass, and configures it for drawing the next frame.
function BaseShading:resetShadowPass()
    self.shadowPass:reset()
    self.shadowPass:setDepthTest("less")
end

--- Configures the shadow pass and light space matrix for a directional light.
---
--- The shadow camera will be orthographic, originating from `pos`, pointing
--- towards `dir`, with a size of `size`. The shadow will be rendered between
--- `near` and `far`.
---
--- @param pos Vec3
--- @param dir Vec3
--- @param size number
--- @param near number
--- @param far number
function BaseShading:sendDirectionalShadow(pos, dir, size, near, far)
    local projection = lovr.math.mat4():orthographic(
        -size, size, -size, size, near, far
    )
    self.shadowPass:setProjection(1, projection)

    local view = lovr.math.mat4():lookAt(pos, pos + dir)
    self.shadowPass:setViewPose(1, view, true)

    self.lightSpaceMatrix = projection * view
end

--- Configures the shadow pass and light space matrix for a spotlight.
---
--- The shadow camera will be perspective, originating from `pos`, pointing
--- towards `dir`, with a field of view of `2 * angle`. The shadow will be
--- rendered between `near` and `far`.
---
--- Yes, it's weird that the angle is doubled. It's based on the spotlight args
--- originally defined by OpenGL. Also the angle is in degrees, again because
--- of OpenGL. Sorry.
---
--- @param pos Vec3
--- @param dir Vec3
--- @param angle number
--- @param near number
--- @param far number
function BaseShading:sendSpotlightShadow(pos, dir, angle, near, far)
    -- Yes, we do need to double the angle to match the spotlight cutoff
    -- parameter, where 90 is a full hemisphere.
    local spotAngle = math.rad(angle * 2)
    local projection = lovr.math.mat4():perspective(spotAngle, 1, near, far)
    self.shadowPass:setProjection(1, projection)

    local view = lovr.math.mat4():lookAt(pos, pos + dir)
    self.shadowPass:setViewPose(1, view, true)

    self.lightSpaceMatrix = projection * view
end

return BaseShading
