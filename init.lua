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

local BaseColorMethods = {}
local BaseColorProps = { r = 1, g = 2, b = 3, a = 4 }
local BaseColor = {
    __index = function(t, k)
        return BaseColorMethods[k] or rawget(t, BaseColorProps[k])
    end,
    __newindex = function(t, k, v)
        error("Color is immutable")
    end
}

local V4Methods = {}
local V4Props = { x = 1, y = 2, z = 3, w = 4 }
local V4 = {
    __index = function(t, k)
        return V4Methods[k] or rawget(t, V4Props[k])
    end,
    __newindex = function(t, k, v)
        error("V4 is immutable")
    end
}

--- @class BaseShading
--- @field shadowPass Pass
--- @field private shadowTexture Texture
--- @field private shadowSampler Sampler
--- @field private lightSpaceMatrix any
local BaseShading = {}
BaseShading.__index = BaseShading

BaseShading.Color = BaseColor --[[@as BaseColor]]
BaseShading.V4 = V4 --[[@as BaseV4]]

--- @param c BaseColor
--- @return BaseColor
function BaseColorMethods.asGamma(c)
    if c.colorSpace ~= "linear" then
        return c
    end

    local r, g, b = lovr.math.linearToGamma(c[1], c[2], c[3]) --[[@as number]]

    return BaseShading.newColor(r, g, b, c[4], "gamma")
end

--- @param c BaseColor
--- @return BaseColor
function BaseColorMethods.asLinear(c)
    if c.colorSpace == "linear" then
        return c
    end

    local r, g, b = lovr.math.gammaToLinear(c[1], c[2], c[3]) --[[@as number]]

    return BaseShading.newColor(r, g, b, c[4], "linear")
end

function V4.__unm(v)
    return BaseShading.newV4(-v[1], -v[2], -v[3], -v[4])
end

function V4.__add(a, b)
    if type(b) == "number" then
        return BaseShading.newV4(a[1] + b, a[2] + b, a[3] + b, a[4] + b)
    else
        return BaseShading.newV4(
            a[1] + b[1], a[2] + b[2], a[3] + b[3], a[4] + b[4]
        )
    end
end

function V4.__sub(a, b)
    if type(b) == "number" then
        return BaseShading.newV4(a[1] - b, a[2] - b, a[3] - b, a[4] - b)
    else
        return BaseShading.newV4(
            a[1] - b[1], a[2] - b[2], a[3] - b[3], a[4] - b[4]
        )
    end
end

function V4.__mul(a, b)
    if type(b) == "number" then
        return BaseShading.newV4(a[1] * b, a[2] * b, a[3] * b, a[4] * b)
    else
        return BaseShading.newV4(
            a[1] * b[1], a[2] * b[2], a[3] * b[3], a[4] * b[4]
        )
    end
end

function V4.__div(a, b)
    if type(b) == "number" then
        return BaseShading.newV4(a[1] / b, a[2] / b, a[3] / b, a[4] / b)
    else
        return BaseShading.newV4(
            a[1] / b[1], a[2] / b[2], a[3] / b[3], a[4] / b[4]
        )
    end
end

--- @param v BaseV4
--- @return vector
function V4Methods.xyz(v)
    return vector(v[1], v[2], v[3])
end

--- @param a BaseV4
--- @param b BaseV4
--- @return number
function V4Methods.distance(a, b)
    return (a - b):length()
end

--- @param a BaseV4
--- @param b BaseV4
--- @return number
function V4Methods.dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
end

--- @param v BaseV4
--- @return number
function V4Methods.length(v)
    return math.sqrt(v:dot(v))
end

--- @param v BaseV4
--- @return BaseV4
function V4Methods.normalize(v)
    return v / v:length()
end

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

--- @param r number
--- @param g number
--- @param b number
--- @param a? number
--- @param colorSpace? BaseColorSpace
--- @return BaseColor
function BaseShading.newColor(r, g, b, a, colorSpace)
    a = a or 1

    if colorSpace == nil then
        colorSpace = "linear"
        r, g, b = lovr.math.gammaToLinear(r, g, b) --[[@as number]]
    end

    return setmetatable({ r, g, b, a, colorSpace = colorSpace }, BaseColor)
end

--- @param x number
--- @param y number
--- @param z number
--- @param w number
--- @return BaseV4
function BaseShading.newV4(x, y, z, w)
    return setmetatable({ x, y, z, w }, V4)
end

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
        spotDirection = props.spotDirection or vector(0, 0, -1),
        position = props.position or BaseShading.newV4(0, 0, 1, 0),
        ambient = props.ambient or BaseShading.newColor(0, 0, 0, 1),
        diffuse = props.diffuse or BaseShading.newColor(0, 0, 0, 1),
        specular = props.specular or BaseShading.newColor(0, 0, 0, 1),
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
        ambient = props.ambient or BaseShading.newColor(0.2, 0.2, 0.2, 1),
        diffuse = props.diffuse or BaseShading.newColor(0.8, 0.8, 0.8, 1),
        emissive = props.emissive or BaseShading.newColor(0, 0, 0, 1),
        specular = props.specular or BaseShading.newColor(0, 0, 0, 1),
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
        color = props.color or BaseShading.newColor(0, 0, 0, 1),
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
    ambient = BaseShading.newColor(0, 0, 0, 1),
    diffuse = BaseShading.newColor(0, 0, 0, 1),
    emissive = BaseShading.newColor(1, 1, 1, 1),
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
    pass:send("baseLights", lightsUniformContainer)
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
--- @param ambient BaseColor
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
--- @param pos vector
--- @param dir vector
--- @param size number
--- @param near number
--- @param far number
function BaseShading:sendDirectionalShadow(pos, dir, size, near, far)
    local projection = lovr.math.newMat4():orthographic(
        -size, size, -size, size, near, far
    )
    self.shadowPass:setProjection(1, projection)

    local view = lovr.math.newMat4():lookAt(pos, pos + dir)
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
--- @param pos vector
--- @param dir vector
--- @param angle number
--- @param near number
--- @param far number
function BaseShading:sendSpotlightShadow(pos, dir, angle, near, far)
    -- Yes, we do need to double the angle to match the spotlight cutoff
    -- parameter, where 90 is a full hemisphere.
    local spotAngle = math.rad(angle * 2)
    local projection = lovr.math.newMat4():perspective(spotAngle, 1, near, far)
    self.shadowPass:setProjection(1, projection)

    local view = lovr.math.newMat4():lookAt(pos, pos + dir)
    self.shadowPass:setViewPose(1, view, true)

    self.lightSpaceMatrix = projection * view
end

return BaseShading
