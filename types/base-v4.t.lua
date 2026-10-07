--- @meta _

--- @class BaseV4
--- @field x number
--- @field y number
--- @field z number
--- @field w number
--- @operator unm: BaseV4
--- @operator add(BaseV4): BaseV4
--- @operator add(number): BaseV4
--- @operator sub(BaseV4): BaseV4
--- @operator sub(number): BaseV4
--- @operator mul(BaseV4): BaseV4
--- @operator mul(number): BaseV4
--- @operator div(BaseV4): BaseV4
--- @operator div(number): BaseV4
local BaseV4 = {}

--- @param v BaseV4
--- @return vector
function BaseV4.xyz(v)
end

--- @param a BaseV4
--- @param b BaseV4
--- @return number
function BaseV4.distance(a, b)
end

--- @param a BaseV4
--- @param b BaseV4
--- @return number
function BaseV4.dot(a, b)
end

--- @param v BaseV4
--- @return number
function BaseV4.length(v)
end

--- @param v BaseV4
--- @return BaseV4
function BaseV4.normalize(v)
end
