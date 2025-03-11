# lovr-base-shading
A simple Phong and fog shading model for LÖVR.

> [!WARNING]
> Prior to v1.0.0, there are no backwards compatibility commitments. Expect
> frequent, major breaking changes.

![Shapes floating in the air over a tile ground.](media/preview.png)

This library implements the Phong lighting model, inspired by pre-shader fixed
function OpenGL lighting. It also supports shadow maps, and simple
distance-based fog. This allows you to get a basic and fairly inexpensive
lighting model up and running in LÖVR quickly if you don't have sophisticated
lighting requirements.

The library is used to create shaders that implement the shading model. To
customize surfaces, you can supply "surface shaders": functions that fill a
struct with color and emissive information for a fragment.

Review the sample `main.lua` file to see the library in use, and consult
documentation comments within `init.lua` and the type files in the `types`
directory.

## Lights

- Up to 8 lights per object
- Vertex and fragment-based lights
- Ambient, diffuse, and specular terms
- Directional, point, and spot lights

## Fog
- Vertex or fragment-based
- Linear, exp, or exp2
- Based on world distance instead of z-depth

## Shadows
- Connected to a single light, or "universally" darken all lights
- Multiple sample PCF for smoother shadows
- Edge fading
