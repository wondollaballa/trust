local Bag = require('cylibs/inventory/bag')
local Equipment = require('cylibs/inventory/equipment/equipment')

local Inventory = {}
Inventory.__index = Inventory
Inventory.__type = "Inventory"

function Inventory.new()
    local self = setmetatable({}, Inventory)
    self.equipment = Equipment.new()
    self.bags = {}
    return self
end

function Inventory:getBag(name)
    if self.bags[name] == nil then
        self.bags[name] = Bag.new(name)
    end
    return self.bags[name]
end

function Inventory:getBags(names)
    local bags = L{}
    for name in names:it() do
        bags:append(self:getBag(name))
    end
    return bags:compact_map()
end

function Inventory:getAllBags()
    return self:getBags(Bag.AllBags)
end

function Inventory:getKeyItems()
    local keyItems = L(windower.ffxi.get_key_items())
    return keyItems
end

function Inventory:getEquipment()
    return self.equipment
end

function Inventory:find(itemId)
    for bag in self:getAllBags():it() do
        local index = bag:findItem(itemId)
        if index ~= -1 then
            return bag, index
        end
    end
    return nil, -1
end

return Inventory

