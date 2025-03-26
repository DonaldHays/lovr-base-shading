-- This sample imports the module via "." since it's in the root of the module.
-- Typically, you would put the module in a subdirectory and import it like
-- `local BaseShading = require "base-shading"`.
local BaseShading = require "."

local base        --- @type BaseShading
local shader      --- @type Shader
local lights = {} --- @type BaseLight[]
local spotlight   --- @type BaseLight
local material    --- @type BaseMaterial
local shadow      --- @type BaseShadow
local fog         --- @type BaseFog
local ambient     --- @type Vec4

function lovr.load()
    -- Create a new `BaseShading` instance. Here we're supplying a custom
    -- resolution for the shadow map, but you can omit that to accept the
    -- default of `512`.
    base = BaseShading:new {
        shadowResolution = 1024,
    }

    -- We use `BaseShading` instances to create shaders that implement the
    -- lighting model. We could supply a surface shader function to customize
    -- the appearance of a surface, but for this example we'll just use the
    -- default.
    shader = base:newSurfaceShader()

    -- Calculate ambient light color.
    local ar, ag, ab = lovr.math.gammaToLinear(0.1, 0.3, 0.5)
    ambient = lovr.math.newVec4(ar, ag, ab, 1)

    -- BaseShading requires 8 lights.
    for _ = 1, 8 do
        table.insert(lights, BaseShading.newLight())
    end

    -- We'll use the first light as a directional light. Note the use of the
    -- position field. Setting `w` to `0` makes the light directional, and it'll
    -- take its direction from the `xyz` components.
    local directional = lights[1]
    local dr, dg, db = lovr.math.gammaToLinear(1.0, 0.9, 0.8)
    directional.mode = BaseShading.LightMode.kVertex
    directional.position:set(-1, 1, 1, 0)
    directional.position:normalize()
    directional.diffuse:set(dr, dg, db, 1.0)

    -- The second light will be a spotlight. It'll also be the light we use for
    -- shadows. The shadow casting light must be a fragment light. To configure
    -- a light to be a spotlight, we set the `w` of the position to `1`, and
    -- `spotCutoff` to a value other than `180`. We store the spotlight in a
    -- module-level variable so we can configure the shadow map during
    -- rendering.
    spotlight = lights[2]
    spotlight.mode = BaseShading.LightMode.kFragment
    spotlight.position:set(2, 2.5, 0, 1)
    spotlight.spotDirection:set(-0.75, -0.75, -1)
    spotlight.spotDirection:normalize()
    spotlight.spotCutoff = 20
    spotlight.diffuse:set(1, 1, 1, 1)
    spotlight.specular:set(1, 1, 1, 1)

    -- Configure the shadow to use our spotlight.
    shadow = BaseShading.newShadow {
        lightIndex = 2
    }

    -- Create a material that has some specularity.
    material = BaseShading.newMaterial {
        specular = lovr.math.newVec4(1, 1, 1, 1),
        shininess = 32
    }

    -- Create some blue fog with a tight linear range.
    local fr, fg, fb = lovr.math.gammaToLinear(0.1, 0.15, 0.2)
    fog = BaseShading.newFog {
        mode = BaseShading.FogMode.kLinear,
        color = lovr.math.newVec4(fr, fg, fb, 1),
        linearStart = 2,
        linearEnd = 7
    }

    -- If we're not on Quest, let's dial up the graphics settings a bit.
    if lovr.system.getOS() ~= "Android" then
        -- Use multiple shadow samples
        shadow.sampleRange = 1
        shadow.pcfScale = 1.0 / 350.0

        -- Switch some vertex calculations to fragment for higher quality.
        directional.mode = BaseShading.LightMode.kFragment
        fog.type = BaseShading.FogType.kFragment
    end
end

function lovr.draw(pass)
    -- The `BaseShading` instance holds the pass we use for shadow mapping.
    local shadowPass = base.shadowPass

    -- We're starting a new frame, so reset the shadow pass.
    base:resetShadowPass()

    -- Prepare the shadow map projection parameters. Note that this is set on
    -- the base shading instance, independently of the surface shader.
    base:sendSpotlightShadow(
        spotlight.position.xyz,
        spotlight.spotDirection,
        spotlight.spotCutoff,
        0.1,
        50
    )

    -- Assign the surface shader to the main pass. We could have multiple
    -- surface shaders for different draw calls, but we only use the one for
    -- this example.
    pass:setShader(shader)

    -- Send all the base shading data to the surface shader. Some of these
    -- parameters are expensive to send, so you should send them as rarely as
    -- possible. Here we only send them once for the whole frame because they're
    -- constant across the entire scene.
    base:sendAmbient(pass, ambient)
    base:sendLights(pass, lights)
    base:sendMaterial(pass, material)
    base:sendShadow(pass, shadow)
    base:sendFog(pass, fog)

    -- Draw the grid.
    for x = -3, 3 do
        for z = -6, 0 do
            -- Alternate between black and white tiles
            if (x + z) % 2 == 0 then
                pass:setColor(0.2, 0.2, 0.2, 1)
            else
                pass:setColor(0.8, 0.8, 0.8, 1)
            end
            pass:plane(x, 0, z, 1, 1, -math.pi * 0.5, 1, 0, 0)
        end
    end

    -- Draw some shapes. Note that we draw to both the main and shadow passes.
    -- The main pass will draw the main image, while the shadow pass draws the
    -- shadow map. Note that we *didn't* draw the grid to the shadow map. The
    -- grid will still *receive* shadows, but it doesn't need to *cast* them,
    -- because it's the ground. As a key optimization, you should minimize how
    -- many things you draw to the shadow map.
    local angle = lovr.headset.getTime()
    pass:setColor(0.5, 1, 0.5, 1)
    pass:sphere(-1.0, 1.0, -2.5, 0.25, angle, -1, 0.5, 0)
    shadowPass:sphere(-1.0, 1.0, -2.5, 0.25, angle, -1, 0.5, 0)

    pass:setColor(1, 0.5, 0.5, 1)
    pass:cube(0.0, 1.0, -2.0, 0.5, angle, 0.5, 1, 0)
    shadowPass:cube(0.0, 1.0, -2.0, 0.5, angle, 0.5, 1, 0)

    pass:setColor(0.5, 0.5, 1, 1)
    pass:cone(1.0, 1.0, -2.5, 0.25, 0.5, angle, 0.75, -1, 0)
    shadowPass:cone(1.0, 1.0, -2.5, 0.25, 0.5, angle, 0.75, -1, 0)

    -- Commit both the shadow and main passes. We specifically pass the shadow
    -- pass first so that the resulting shadow map may be used by the main pass.
    return lovr.graphics.submit(base.shadowPass, pass)
end
