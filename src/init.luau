--!strict

local Cursor = require("@self/Cursor")

-- value type codes
local TY_NIL = 0
local TY_STRING  = 1
local TY_NUMBER  = 2
local TY_TRUE = 3
local TY_FALSE = 4
local TY_TABLE = 5
local TY_NEST = 6
local TY_VECTOR = 7

local Module = {}

local pushtab, poptab

local function pushvalue(cursor: Cursor.Cursor, val: nil | string | number | boolean | vector | (any & {}))
	local keyType = type(val)
	assert(keyType ~= "function" and keyType ~= "thread" and keyType ~= "userdata")

	if val == nil then
		Cursor.pushu1(cursor, TY_NIL)
	elseif val == true then
		Cursor.pushu1(cursor, TY_TRUE)
	elseif val == false then
		Cursor.pushu1(cursor, TY_FALSE)
	elseif type(val) == "number" then
		Cursor.pushf8(cursor, val)
		Cursor.pushu1(cursor, TY_NUMBER)
	elseif type(val) == "string" then
		Cursor.pushstr(cursor, val)
		Cursor.pushu1(cursor, TY_STRING)
	elseif type(val) == "table" then
		pushtab(cursor, val)
		Cursor.pushu1(cursor, TY_TABLE)
	elseif type(val) == "vector" then
		Cursor.pushvector3f4(cursor, val)
		Cursor.pushu1(cursor, TY_VECTOR)
	else
		error(`Invalid key {val} : {type(val)}`)
	end
end

local function popvalue(cursor: Cursor.Cursor, ty: number): nil | string | number | boolean | vector | (any & {})
	if ty == TY_NIL then
		return nil
	elseif ty == TY_TRUE then
		return true
	elseif ty == TY_FALSE then
		return false
	elseif ty == TY_NUMBER then
		return Cursor.popf8(cursor)
	elseif ty == TY_STRING then
		return Cursor.popstr(cursor)
	elseif ty == TY_TABLE then
		return poptab(cursor)
	elseif ty == TY_VECTOR then
		return Cursor.popvector3f4(cursor)
	else
		error(`Invalid kind {ty}`)
	end
end

function pushtab(cursor: Cursor.Cursor, tab: any & {})
	local propertyCount = 0
	for key, value in pairs(tab) do
		propertyCount += 1
		pushvalue(cursor, value)
		pushvalue(cursor, key)
	end

	Cursor.pushvlq(cursor, propertyCount)
end

function poptab(cursor: Cursor.Cursor): any & {}
	local tab = {}

	local propertyCount = Cursor.popvlq(cursor)
	for _ = 1, propertyCount do
		local keyTy = Cursor.popu1(cursor)
		local key = popvalue(cursor, keyTy)

		local valueTy = Cursor.popu1(cursor)
		local value = popvalue(cursor, valueTy)

		tab[key] = value
	end

	return tab
end

local function pushdiff(cursor: Cursor.Cursor, deltas, new, old)
	local length = 0

	for oldK, oldV in pairs(old) do
		if new[oldK] == nil then
			pushvalue(cursor, nil)
			pushvalue(cursor, oldK)
			length += 1
		end
	end

	for newK, newV in pairs(new) do
		local oldV = old[newK]
		if newV == oldV then
			continue
		end

		if type(newV) == "table" and type(oldV) == "table" then
			local deltasKey = {}
			local len = pushdiff(cursor, deltasKey, newV, oldV)
			if len > 0 then
				deltas[newK] = deltasKey
				pushvalue(cursor, newK)
				Cursor.pushu1(cursor, TY_NEST)
				length += 1
			end
		else
			deltas[newK] = newV :: any
			pushvalue(cursor, newV)
			pushvalue(cursor, newK)
			length += 1
		end
	end

	Cursor.pushvlq(cursor, length)

	return length
end

local function popdiff(cursor: Cursor.Cursor, target, deltas)
	local length = Cursor.popvlq(cursor)
	for _ = 1, length do
		local ty = Cursor.popu1(cursor)
		if ty == TY_NEST then
			local keyTy = Cursor.popu1(cursor)
			local key = popvalue(cursor, keyTy)
			target[key] = if type(target[key]) == "table" then target[key] else {}

			local deltasKey = {}
			deltas[key] = deltasKey

			popdiff(cursor, target[key], deltasKey)
		else
			local key = popvalue(cursor, ty)

			local valTy = Cursor.popu1(cursor)
			local val = popvalue(cursor, valTy)

			target[key] = val :: any
			deltas[key] = val :: any
		end
	end
end

--[[
	Deep clones a table, usually used to save a snapshot of old data before diffing or applying.
	Exmaple 1:
	```lua
	local oldData = DeepDelta.clone(data)
	mutateData(data)
	local diff, deltas = DeepDelta.diff(data, oldData)
	```
	---
	Example 2:
	```lua
	local oldData = DeepDelta.clone(data)
	local deltas, DeepDelta.apply(data, diff)
	DataChanged:Fire(data, oldData, deltas)
	```
]]
local function deepClone<T>(tab: T & {}): T
	local new = table.clone(tab)
	for k, v in new do
		if type(v) == "table" then
			new[k] = deepClone(v :: any)
		end
	end
	return new :: any
end

Module.clone = deepClone

--[[
	Serializes the deep delta between two tables into a buffer for applying to a table later.

	```lua
	local oldData = DeepDelta.clone(data)
	data.money -= 10
	local row = math.random(1, #data.loot)
	table.insert(data.loot[row], {
		rarity = "rare",
		duration = 300, -- seconds
	})
	local diff, deltas = DeepDelta.diff(data, oldData)
	```
]]
function Module.diff<T>(new: T & {}, old: any & {}): (buffer, T)
	local deltas = {} :: any
	local cursor = Cursor.new()
	pushdiff(cursor, deltas, new, old)
	return Cursor.tobuffer(cursor), deltas
end

--[[
	Applies a previously serialized deep delta diff to a table.

	```lua
	local oldData = DeepDelta.clone(data)
	local deltas = DeepDelta.apply(data, diff)
	DataChanged:Fire(data, oldData, deltas)
	```
]]
function Module.apply(target: any & {}, diff: buffer)
	local deltas = {}
	local cursor = Cursor.frombuffer(diff)
	popdiff(cursor, target, deltas)
	return deltas
end

return Module
