--- @meta _

--- @alias BaseColorSpace "gamma" | "linear"

--- @class BaseColor
--- @field r number
--- @field g number
--- @field b number
--- @field a number
--- @field colorSpace? BaseColorSpace
local BaseColor = {}

--- @param c BaseColor
--- @return BaseColor
function BaseColor.asGamma(c)
end

--- @param c BaseColor
--- @return BaseColor
function BaseColor.asLinear(c)
end
