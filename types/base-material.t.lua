--- @meta _

--- A type that represents a material.
---
--- Materials may be created using `BaseShading.newMaterial(props)`. See that
--- API for default values.
---
--- A material may define how it interacts with lights using the `ambient`,
--- `diffuse`, and `specular` fields. These values are multiplied by the
--- corresponding values in the light.
---
--- The `emissive` field causes the object to emit light itself, even in the
--- absence of any light sources. However, the light will only affect the object
--- it's assigned to, and will not illuminate other objects.
---
--- The `shininess` field determines the size of the specular highlight. Higher
--- values will concentrate the highlight into a smaller area.
---
--- @class BaseMaterial
--- @field ambient? Vec4
--- @field diffuse? Vec4
--- @field emissive? Vec4
--- @field specular? Vec4
--- @field shininess? number
