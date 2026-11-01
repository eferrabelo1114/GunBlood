--!strict

local TableUtil = {}

function TableUtil.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in value :: any do
		copy[key] = TableUtil.DeepCopy(child)
	end
	return copy :: any
end

return TableUtil
