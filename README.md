# DeepDelta

![DeepDeltaLogo_1024x484](/Assets/DeepDelta_1024x484.webp)

A Luau library that serializes nested table diffs into buffers. Similar to [DeltaCompress](https://nezuo.github.io/delta-compress/), but supporting nested tables. Future updates to improve compression size are likely.

## API
`DeepDelta.clone(tab: T): T`

Deep clones a table, usually used to save a snapshot of old data before diffing or applying.

```lua
-- Server
local oldData = DeepDelta.clone(data)
mutateData(data)
local diff = DeepDelta.diff(data, oldData)
```
```lua
-- Client
local oldData = DeepDelta.clone(data)
DeepDelta.apply(data, diff)
DataChanged:Fire(data, oldData)
```
---
`DeepDelta.diff(new: table, old: table): buffer`

Serializes the deep delta between two tables into a buffer for applying to a table later.

```lua
local oldData = DeepDelta.clone(data)

data.money -= 10

local row = math.random(1, #data.loot)
table.insert(data.loot[row], {
	rarity = "rare",
	duration = 300, -- seconds
})

local diff = DeepDelta.diff(data, oldData)
DataUpdated:Fire(diff)
```
---
`DeepDelta.apply(target: table, diff: buffer)`

Applies a previously serialized deep delta diff to a table.

```lua
local oldData = DeepDelta.clone(data)
DeepDelta.apply(data, diff)
DataChanged:Fire(data, oldData)
```
