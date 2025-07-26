local Inventories = {}
local QBCore = exports['qb-core']:GetCoreObject()

function genSerial()
    local seed = math.randomseed(math.random(0, 99999999))
    local serial = math.random(100000, 99999999)
    return serial
end

function getDropInventories()
    local drops = {}

    for id, data in pairs(Inventories) do
        if data.type == "drop" then
            drops[id] = data
        end

        Wait(100)
    end

    return drops
end

function splitString(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

function executeUpdateQuerys(id)
    local items = json.encode(Inventories[id].items)
    local maxweight = json.encode(Inventories[id].maxweight)
    local slots = json.encode(Inventories[id].slots)

    local querys = {
        update = {
            query = 'UPDATE inventory SET items = @items, maxweight = @maxweight, slots = @slots WHERE inv_id = @inv_id',
            data = {
                ['@items'] = items,
                ['@inv_id'] = id,
                ['@maxweight'] = maxweight,
                ['@slots'] = slots
            }
        },
        insert = {
            query =
            'INSERT INTO inventory (inv_id, items, type, maxweight, slots) VALUES (@inv_id, @items, @type, @maxweight, @slots)',
            data = {
                ['@inv_id'] = id,
                ['@items'] = items,
                ['@type'] = Inventories[id].type,
                ['@maxweight'] = maxweight,
                ['@slots'] = slots
            }
        }
    }

    MySQL.update(querys.update.query, querys.update.data, function(rowsChanged)
        if rowsChanged == 0 then
            MySQL.insert(querys.insert.query, querys.insert.data, function(rowsChanged)
                if rowsChanged == 0 then
                    print("Error al guardar el inventario")
                end
            end)
        end
    end)

    Inventories[id].cache.last_inv_update = os.time()
end

function LoadInventory(id)
    local id_data = splitString(id, "-")

    if #id_data < 2 or #id_data > 2 then return false end

    return MySQL.single('SELECT * FROM inventory WHERE inv_id = ? LIMIT 1', { id }, function(row)
        data = {}
        if not row then
            data.id = id
            data.items = {}
            data.type = id_data[2]
            data.open = false
            data.slots = Config.MaxInventorySlots
            data.maxweight = Config.MaxInventoryWeight
            
            data.cache = {}
            data.cache.last_inv_update = os.time()

            Inventories[data.id] = data

            return data
        end

        local tempItemslist = {}

        for id, item in pairs(json.decode(row.items)) do
            tempItemslist[item.slot] = item 
        end

        data.id = row.inv_id
        data.items = tempItemslist
        data.type = row.type
        data.open = false
        data.slots = row.slots
        data.maxweight = row.maxweight
        data.cache = {}
        data.cache.last_inv_update = os.time()

        Inventories[data.id] = data

        return data.items
    end)
end

function saveInventory(id)
    if Inventories[id] == nil then return end
    if Inventories[id].type == "drop" then return end

    if Inventories[id].type == "trunk" or Inventories[id].type == "glovebox" then
        local id_data = splitString(id, "-")
        local ownedVehicle = MySQL.Sync.fetchScalar('SELECT plate FROM player_vehicles WHERE plate = @plate',
            { ['@plate'] = id_data[1] })

        if not ownedVehicle then return end
        executeUpdateQuerys(id)
    else
        executeUpdateQuerys(id)
    end
end

function createWeaponInfo()
    local info = {}
    info.serie = genSerial()
    info.quality = 100
    info.ammo = 0
    info.tint = 0
    return info
end

function createItemData(sourceItem, amount, slot, info)
    return {
        name = sourceItem.name,
        info = sourceItem.info or info or {},
        label = sourceItem.label,
        description = sourceItem.description,
        weight = sourceItem.weight,
        type = sourceItem.type,
        unique = sourceItem.unique,
        useable = sourceItem.useable,
        image = sourceItem.image,
        shouldClose = sourceItem.shouldClose,
        combinable = sourceItem.combinable,
        amount = amount,
        slot = slot
    }
end

-- 🧪 Guardando los inventarios cada cierto tiempo
CreateThread(function()
    while true do
        for id, data in pairs(Inventories) do
            if data.cache.last_inv_update and
               (os.time() - data.cache.last_inv_update) >= Config.InventoryUpdateCooldown then
                print("Guardando inventario: " .. id)
                saveInventory(id)
            end
        end
        Wait(Config.InventoryUpdateCooldown * 1000)
    end
end)

--[[ AddEventHandler('QBCore:Server:OnMoneyChange', function(src, moneyType, amount, type, reason)
    local id = formatInventoryId(src)

    if not Inventories[id] then return end

    if moneyType ~= "cash" then
        if type ~= "remove" then
            RemoveItem(id, "cash", amount)
        elseif
            AddItem(id, "cash", amount) then
        end
    end

    TriggerClientEvent("inventory:cl:updateInventory", src, Inventories[id])
end) ]]


function swapItem(fromId, toId, fromSlot, toSlot, fromAmount, toAmount, source, secondInventory)
    local fromSlot = tonumber(fromSlot)
    local toSlot = tonumber(toSlot) or getFreeSlot(source)
    local fromAmount = tonumber(fromAmount)
    local fromItem = Inventories[fromId].items[fromSlot]


    print("Swapping item from " .. fromId .. " slot " .. fromSlot .. " to " .. toId .. " slot " .. toSlot)

    -- weapon stack
    if fromItem.type == "weapon" and toId ~= nil and Inventories[toId] and Inventories[toId].items[toSlot] then
        local toItem = Inventories[toId].items[toSlot]
        if toItem.type == "weapon" and fromItem.info.serie ~= nil or toItem.info.serie ~= nil then
            return
        end
    end

    if not Inventories[fromId] or not Inventories[fromId].items[fromSlot] then return end
    if Inventories[fromId].items[fromSlot].amount < fromAmount then return end
    if Inventories[toId] and Inventories[toId].type == "shop" then return end

    -- Money as item checks 
--[[ 

    local fromPlayer = QBCore.Functions.GetPlayer(source)
    -- local toPlayer = QBCore.Functions.GetPlayerByCitizenId(splitString(toId, "-")[1])

    if fromId ~= toId and fromItem.name == "cash" then
        fromPlayer.Functions.RemoveMoney('cash', fromAmount, "inventory-transaction")
        if Inventories[toId].type == "player" then
            local toPlayer = QBCore.Functions.GetPlayerByCitizenId(splitString(toId, "-")[1])
            toPlayer.Functions.AddMoney('cash', fromAmount, "inventory-transaction")
        end
    end ]]

    -- Bags item limitation
    if Inventories[toId] and Inventories[toId].type == "bag" then
        if Inventories[fromId].items[fromSlot].type ~= Inventories[toId].item_limit and Inventories[toId].item_limit ~= nil then
            return
        end
    end

    --[[ SISTEMA PAGO PARA TIENDAS ]]
    if Inventories[fromId].type == "shop" then
        local Player = QBCore.Functions.GetPlayer(source)
        local price = Inventories[fromId].items[fromSlot].price * fromAmount

        if Player.PlayerData.money.cash < price then
            if Player.PlayerData.money.bank < price then
                QBCore.Functions.Notify(source, "El inventario parece estar siendo usado...", 'error')
                return
            else
                Player.Functions.RemoveMoney('bank', price, "shop-bought-item")
            end
        else
            Player.Functions.RemoveMoney('cash', price, "shop-bought-item")
        end
    end

    if toId == tostring(0) then
        local id = tostring(math.random(10000, 9999999)) .. "-drop"
        local pedCoords = GetEntityCoords(GetPlayerPed(source))

        Inventories[id] = {
            items = {},
            type = 'drop',
            id = id,
            open = false,
            slots = Config.MaxInventorySlots,
            coords = pedCoords,
            maxweight = Config.MaxInventoryWeight
        }

        toId = id

        TriggerClientEvent("inventory:cl:createDropItem", -1, toId, pedCoords)
    end

    if not toId then return end
    local toItem = Inventories[toId].items[toSlot]

    if toItem == nil then
        if fromItem.amount > fromAmount then
            
            Inventories[fromId].items[fromSlot].amount = fromItem.amount - fromAmount
            Inventories[toId].items[toSlot] = createItemData(fromItem, fromAmount, toSlot)

            if Inventories[fromId].items[fromSlot].type == "weapon" and Inventories[fromId].items[fromSlot].amount == 1 then
                Inventories[fromId].items[fromSlot].info = createWeaponInfo()
                saveInventory(fromId)
            end

            if Inventories[toId].items[toSlot].type == "weapon" and fromAmount == 1 then
                Inventories[toId].items[toSlot].info = createWeaponInfo()
                saveInventory(toId)
            end

        elseif fromItem.amount == fromAmount then
            Inventories[toId].items[toSlot] = createItemData(fromItem, fromAmount, toSlot)            
            Inventories[fromId].items[fromSlot] = nil
        end
    else
        if fromItem.name == toItem.name then
            Inventories[fromId].items[fromSlot].amount = fromItem.amount - fromAmount

            if Inventories[fromId].items[fromSlot].amount == 0 then
                Inventories[fromId].items[fromSlot] = nil
            end

            Inventories[toId].items[toSlot].amount = toItem.amount + fromAmount
        else

            Inventories[fromId].items[fromSlot] = createItemData(toItem, toAmount, fromSlot)

            -- Validating amount changed correctly
            if Inventories[fromId].items[fromSlot].amount < toAmount then
                Inventories[fromId].items[fromSlot].amount = toAmount
            end

            Inventories[toId].items[toSlot] = createItemData(fromItem, fromAmount, toSlot)


            if Inventories[toId].items[toSlot].amount < fromAmount then
                Inventories[toId].items[toSlot].amount = fromAmount
            end
        end
    end

    -- Updating Client Interfaces
    local sourceInventoryId = formatInventoryId(source)

    local fromWeight = GetInventoryWeigth(fromId)
    local toWeight = GetInventoryWeigth(toId)

    Inventories[fromId].weight = fromWeight
    Inventories[toId].weight = toWeight

    if Inventories[fromId] == Inventories[toId] and Inventories[fromId].type == "player" then
        TriggerClientEvent("inventory:cl:updateInventory", source, Inventories[sourceInventoryId], Inventories[secondInventory])
    else
        if toId == sourceInventoryId then
            TriggerClientEvent("inventory:cl:updateInventory", source, Inventories[sourceInventoryId], Inventories[fromId])
        else
            TriggerClientEvent("inventory:cl:updateInventory", source, Inventories[sourceInventoryId], Inventories[toId])
        end
    end

    if Inventories[fromId].type == "drop" and #Inventories[fromId].items == 0 then
        Inventories[fromId] = nil
        TriggerClientEvent("inventory:cl:removeDropItem", -1, fromId)
        TriggerClientEvent("inventory:cl:closeInventory", source)
    end
end

function getFreeSlot(source)
    local id = formatInventoryId(source)

    for i = 1, Config.MaxInventorySlots, 1 do
        if not Inventories[id].items[i] then
            return i
        end
    end

    return nil
end

function formatInventoryId(id)
    if tonumber(id) ~= nil and tonumber(id) ~= 0 then
        local player_citizenid = QBCore.Functions.GetPlayer(tonumber(id)).PlayerData.citizenid
        id = player_citizenid .. "-player"
    end
    return id
end

function UpdateInventoryItems(id)
    local id = formatInventoryId(id)
    if Inventories[id].type ~= "player" then return end
    local citizenid = splitString(id, "-")[1]
    local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)

    if Player ~= nil then
        Player.Functions.SetPlayerData('items', Inventories[id].items)
    end
end

function GetItemsByName(src, name)
    local id = formatInventoryId(src)
    local items = {}
    if not Inventories[id] then return end

    for index, item in pairs(Inventories[id].items) do
        if item.name == name then
            table.insert(items, item)
        end
    end

    return items
end

function GetItemCount(src, name)
    local id = formatInventoryId(src)
    local count = 0
    local slots = {}
    local bag = {}

    if not Inventories[id] then return end

    for index, item in pairs(Inventories[id].items) do
        if item.type == "bag" then
            if not Inventories[item.info.id .. "-bag"] then
                LoadInventory(item.info.id .. "-bag")
                Wait(250)
            end

            local bag_items = Inventories[item.info.id .. "-bag"].items
            for bindex, bitem in pairs(bag_items) do
                if bitem.name == name then
                    count = count + bitem.amount
                    bag[item.info.id .. "-bag"] = {}
                    table.insert(bag[item.info.id .. "-bag"], bitem.slot)
                end
            end
        end

        if item.name == name then
            table.insert(slots, index)
            count = count + item.amount
        end
    end

    return count, slots, bag
end

function HasItem(source, item, amount)
    local count, slots = GetItemCount(source, item)

    if amount == nil then
        amount = 1
    end

    return count >= amount
end

function GetInventory(source)
    local id = formatInventoryId(source)
    if not Inventories[id] then return nil end
    return Inventories[id]
end

function AddItem(source, item, amount, slot, info)
    if not source then return end

    local id = formatInventoryId(source)

    local itemInfo = QBCore.Shared.Items[item]

    if not itemInfo then return false end

    if not Inventories[id] then
        LoadInventory(id)
    end

    Wait(250)

    if not Inventories[id] then return false end

    local slot = slot or getFreeSlot(id)
    local searchItem = GetItemByName(source, item)

    if searchItem ~= nil and not searchItem.unique then
        slot = searchItem.slot
        Inventories[id].items[slot].amount = Inventories[id].items[slot].amount + amount

        if Inventories[id].type == "player" then
            Inventories[id].weight = GetInventoryWeigth(id)
            TriggerClientEvent("inventory:cl:updateInventory", source, Inventories[id])
            UpdateInventoryItems(id)
        end

        return true
    end

    if not Inventories[id].items[slot] then
        Inventories[id].items[slot] = {}
        Inventories[id].items[slot] = {
            name = itemInfo['name'],
            info = itemInfo['info'] or info or {},
            label = itemInfo['label'],
            description = itemInfo['description'] or '',
            weight = itemInfo['weight'],
            type = itemInfo['type'],
            unique = itemInfo['unique'],
            useable = itemInfo['useable'],
            image = itemInfo['image'],
            shouldClose = itemInfo['shouldClose'],
            combinable = itemInfo['combinable'],
            amount = amount,
            slot = slot
        }

        if amount == 1 and Inventories[id].items[slot].type == "weapon" then
            Inventories[id].items[slot].info.serie = genSerial()
            Inventories[id].items[slot].info.quality = 100
            Inventories[id].items[slot].info.ammo = 0
            Inventories[id].items[slot].info.tint = 0
        end

        Inventories[id] = Inventories[id]

        if Inventories[id].type == "player" then
            TriggerClientEvent("inventory:cl:updateInventory", source, Inventories[id])
        end

        saveInventory(id)
        UpdateInventoryItems(id)
        return true
    end

    return nil
end

function RemoveItem(src, item, amount, slot)
    local id = formatInventoryId(src)
    local amount_removed = 0

    if not Inventories[id] then return end

    if slot then
        if not Inventories[id].items[slot] then return end
        if not Inventories[id].items[slot].name == item then return end

        if Inventories[id].items[slot].type == "weapon" and Inventories[id].type == "player" then
            TriggerClientEvent("inventory_client:CheckWeapon", src, Inventories[id].items[slot].name)
        end

        if Inventories[id].items[slot].amount > amount then
            Inventories[id].items[slot].amount = Inventories[id].items[slot].amount - amount
            amount_removed = amount
        elseif Inventories[id].items[slot].amount == amount then
            Inventories[id].items[slot] = nil
            amount_removed = amount
        end
    else
        -- eliminar getItemSlots
        local item_amount, item_slots, bag_slots = GetItemCount(src, item)

        if item_amount < amount then return end

        for index, slot in pairs(item_slots) do
            if Inventories[id].items[slot].type == "weapon" and Inventories[id].type == "player" then
                TriggerClientEvent("inventory_client:CheckWeapon", src, Inventories[id].items[slot].name)
            end

            if Inventories[id].items[slot].amount > amount then
                Inventories[id].items[slot].amount = Inventories[id].items[slot].amount - amount
                amount_removed = amount
                break
            elseif Inventories[id].items[slot].amount == amount then
                Inventories[id].items[slot] = nil
                amount_removed = amount
                break
            else
                local item_amount = Inventories[id].items[slot].amount
                if (item_amount + amount_removed) < amount then
                    Inventories[id].items[slot] = nil
                    amount_removed = amount_removed + item_amount
                elseif (item_amount + amount_removed) == amount then
                    Inventories[id].items[slot] = nil
                    amount_removed = amount
                else
                    local restant = amount - amount_removed
                    if not restant == 0 then
                        Inventories[id].items[slot].amount = Inventories[id].items[slot].amount - restant
                    end
                end
            end
        end

        if amount_removed < amount then
            for index, data in pairs(bag_slots) do
                local id = index
                for index, slot in pairs(data) do
                    if Inventories[id].items[slot].type == "weapon" and Inventories[id].type == "player" then
                        TriggerClientEvent("inventory_client:CheckWeapon", src, Inventories[id].items[slot].name)
                    end

                    if Inventories[id].items[slot].amount > amount then
                        Inventories[id].items[slot].amount = Inventories[id].items[slot].amount - amount
                        amount_removed = amount
                        break
                    elseif Inventories[id].items[slot].amount == amount then
                        Inventories[id].items[slot] = nil
                        amount_removed = amount
                        break
                    else
                        local item_amount = Inventories[id].items[slot].amount
                        if (item_amount + amount_removed) < amount then
                            Inventories[id].items[slot] = nil
                            amount_removed = amount_removed + item_amount
                        elseif (item_amount + amount_removed) == amount then
                            Inventories[id].items[slot] = nil
                            amount_removed = amount
                        else
                            local restant = amount - amount_removed
                            if not restant == 0 then
                                Inventories[id].items[slot].amount = Inventories[id].items[slot].amount - restant
                            end
                        end
                    end
                end
                UpdateInventoryItems(id)
            end
        end
    end
    
    saveInventory(id)
    UpdateInventoryItems(id)

    return (amount_removed == amount)
end

function OpenInventory(tipo, id, other, invid)
    local player_inv = formatInventoryId(invid)

    if not Inventories[player_inv] then
        LoadInventory(player_inv)
        Wait(250)
    end

    if Inventories[player_inv].open then
        QBCore.Functions.Notify(invid, "El inventario parece estar siendo usado...", 'error')
        return
    end

    Inventories[player_inv].weight = GetInventoryWeigth(player_inv)

    -- Cuando el inv es un stash / glovebox / trunk / shop
    if tipo and id then
        if tipo ~= "shop" then
            local invId = id .. "-" .. tipo
            if not Inventories[invId] then
                LoadInventory(invId)
                Wait(250)
            end
            if Inventories[invId].open then
                QBCore.Functions.Notify(invid, "El inventario parece estar siendo usado...", 'error')
                TriggerEvent("inventory:setOpenState", player_inv, false)
                return
            end

            if other then
                Inventories[invId].slots = tonumber(other.slots)
                Inventories[invId].maxweight = tonumber(other.maxweight)
                if other.item_limit then
                    Inventories[invId].item_limit = other.item_limit
                end
            end

            Inventories[invId].weight = GetInventoryWeigth(invId)
            TriggerClientEvent("inventory:cl:OpenInventory", invid, nil, Inventories[player_inv], Inventories[invId])
            TriggerEvent("inventory:setOpenState", invId, true)
            TriggerClientEvent("inventory_client:setSecondInv", invid, invId)
        else
            local shop_id = id .. "-" .. tipo

            Inventories[shop_id] = {
                items = {},
                type = 'shop',
                id = shop_id,
                open = false,
                slots = 50,
                maxweight = 750000
            }

            local shopItemList = {}

            for index, item in pairs(other.items) do
                local itemInfo = QBCore.Shared.Items[item.name]
                if itemInfo then
                    shopItemList[#shopItemList + 1] = {
                        name = itemInfo.name,
                        label = itemInfo.label,
                        description = itemInfo.description,
                        weight = itemInfo.weight,
                        type = itemInfo.type,
                        unique = itemInfo.unique,
                        info = {},
                        useable = itemInfo.useable,
                        image = itemInfo.image,
                        shouldClose = itemInfo.shouldClose,
                        combinable = itemInfo.combinable,
                        amount = item.amount,
                        slot = item.slot,
                        price = item.price
                    }
                end
            end

            Inventories[shop_id].items = shopItemList

            Wait(250)

            Inventories[shop_id].weight = GetInventoryWeigth(shop_id)
            TriggerClientEvent("inventory:cl:OpenInventory", invid, nil, Inventories[player_inv], Inventories[shop_id])
        end

        -- Cuando el inv es un drop
    elseif tipo == nil and id ~= nil then
        if id and Inventories[id] then
            Inventories[id].weight = GetInventoryWeigth(id)
            if Inventories[id].open then
                QBCore.Functions.Notify(invid, "El inventario parece estar siendo usado...", 'error')
                TriggerEvent("inventory:setOpenState", player_inv, false)
                TriggerClientEvent("inventory:cl:OpenInventory", invid, nil, Inventories[player_inv], nil)
                return
            end
        end

        TriggerEvent("inventory:setOpenState", id, true)
        TriggerClientEvent("inventory:cl:OpenInventory", invid, nil, Inventories[player_inv], Inventories[id])
    else
        TriggerClientEvent("inventory:cl:OpenInventory", invid, nil, Inventories[player_inv], nil)
    end
end

local function GetUsableItem(itemName)
    return QBCore.Functions.CanUseItem(itemName)
end

function GetInventoryWeigth(source)
    local weight = 0
    local id = formatInventoryId(source)

    if not Inventories[id] then return end

    for index, item in pairs(Inventories[id].items) do
        weight = weight + (item.weight * item.amount)
    end

    return weight
end

function GetItemByName(source, item)
    local id = formatInventoryId(source)

    if not Inventories[id] then return nil end

    for index, iitem in pairs(Inventories[id].items) do
        if iitem.name == item then
            return Inventories[id].items[index]
        end
    end

    return nil
end

function UseItem(itemName, ...)
    local itemData = QBCore.Functions.CanUseItem(itemName)
    if type(itemData) == "table" and itemData.func then
        itemData.func(...)
    end
end

--[[ TRIGGERS ]]
RegisterNetEvent('inventory:server:UseItemSlot', function(slot)
    local src = source
    local player_citizenid = QBCore.Functions.GetPlayer(src).PlayerData.citizenid
    if not Inventories[player_citizenid .. "-player"] then return end
    local itemData = Inventories[player_citizenid .. "-player"].items[slot]
    if not itemData then return end

    if itemData.type == "weapon" and itemData.amount > 1 then
        QBCore.Functions.Notify(src, "Hay mas de un item en este slot, intenta usar 1 solo...", 'error')
        return nil
    end

    local itemInfo = QBCore.Shared.Items[itemData.name]
    if itemData.type == "weapon" then
        TriggerClientEvent("inventory_client:UseWeapon", src, itemData,
            itemData.info.quality and itemData.info.quality > 0)
    elseif itemData.useable then
        UseItem(itemData.name, src, itemData)
    end
end)

RegisterNetEvent('inventory:server:UseItem', function(inventory, item)
    local src = source
    local inv_type = splitString(inventory, "-")[2]

    if inv_type ~= "player" then return end

    local player_citizenid = QBCore.Functions.GetPlayer(src).PlayerData.citizenid
    local itemData = Inventories[player_citizenid .. "-player"].items[item.slot]

    if not itemData then return end

    local itemInfo = QBCore.Shared.Items[itemData.name]

    if itemData.type == "weapon" then
        TriggerClientEvent("inventory_client:UseWeapon", src, itemData,
            itemData.info.quality and itemData.info.quality > 0)
    else
        UseItem(itemData.name, src, itemData)
    end
end)

--[[ ATTACHMENTS ]]

function GetWeaponSlotByName(source, name)
    local id = formatInventoryId(source)

    if not Inventories[id] then return end

    for index, item in pairs(Inventories[id].items) do
        if item.name == name then
            return item, index
        end
    end
end

function HasAttachment(component, attachments)
    for k, v in pairs(attachments) do
        if v.component == component then
            return true, k
        end
    end
    return false, nil
end

function DoesWeaponTakeWeaponComponent(item, weaponName)
    if WeaponAttachments[item] and WeaponAttachments[item][weaponName] then
        return WeaponAttachments[item][weaponName]
    end
    return false
end

function EquipWeaponAttachment(src, item)
    local ped = GetPlayerPed(src)
    local id = formatInventoryId(src)
    local selectedWeaponHash = GetSelectedPedWeapon(ped)
    if selectedWeaponHash == `WEAPON_UNARMED` then return end

    local weaponName = QBCore.Shared.Weapons[selectedWeaponHash].name
    if not weaponName then return end

    local attachmentComponent = DoesWeaponTakeWeaponComponent(item, weaponName)

    if not attachmentComponent then
        TriggerClientEvent('QBCore:Notify', src, 'This attachment is not valid for the selected weapon.', 'error')
        return
    end

    local weaponSlot, weaponSlotIndex = GetWeaponSlotByName(src, weaponName)

    if not weaponSlot then return end

    weaponSlot.info.attachments = weaponSlot.info.attachments or {}

    local hasAttach, attachIndex = HasAttachment(attachmentComponent, weaponSlot.info.attachments)

    if not hasAttach then
        if not Inventories[id].items[weaponSlotIndex] then return end

        Inventories[id].items[weaponSlotIndex].info.attachments = Inventories[id].items[weaponSlotIndex].info
            .attachments or {}

        Inventories[id].items[weaponSlotIndex].info.attachments[#Inventories[id].items[weaponSlotIndex].info.attachments + 1] = {
            component = attachmentComponent,
            label = item
        }

        GiveWeaponComponentToPed(ped, selectedWeaponHash, attachmentComponent)
        RemoveItem(src, item, 1)
    end

    TriggerClientEvent("inventory:cl:updateInventory", src, Inventories[id])
end

function searchAttachment(item, attachment)
    for index, attach in pairs(item.info.attachments) do
        if tostring(attach.component) == tostring(attachment) then
            return index
        end
    end

    return nil
end

-- Crear item de attachment
for attachmentItem in pairs(WeaponAttachments) do
    QBCore.Functions.CreateUseableItem(attachmentItem, function(source, item)
        EquipWeaponAttachment(source, item.name)
    end)
end

QBCore.Functions.CreateCallback('inventory:server:HasItem', function(source, cb, item, amount)
    cb(HasItem(source, item, amount))
end)

QBCore.Functions.CreateCallback('inventory:server:HowMuchItems', function(source, cb, item)
    cb(GetItemCount(source, item))
end)

QBCore.Functions.CreateCallback('inventory:server:GetInventory', function(source, cb)
    cb(GetInventory(source))
end)

QBCore.Functions.CreateCallback('weapons:server:RemoveAttachment', function(source, cb, slot, attachment)
    local src = source
    local ped = GetPlayerPed(src)
    local id = formatInventoryId(src)

    if not Inventories[id] then
        cb(false)
        return
    end
    if not Inventories[id].items[slot] then
        cb(false)
        return
    end
    if not Inventories[id].items[slot].info.attachments then
        cb(false)
        return
    end

    local attachmentIndex = searchAttachment(Inventories[id].items[slot], attachment)
    local selectedWeaponHash = GetSelectedPedWeapon(ped)
    local component = Inventories[id].items[slot].info.attachments[attachmentIndex].component
    local label = Inventories[id].items[slot].info.attachments[attachmentIndex].label

    if attachmentIndex ~= nil and selectedWeaponHash ~= `WEAPON_UNARMED` then
        RemoveWeaponComponentFromPed(ped, selectedWeaponHash, component)
    end

    AddItem(src, label, 1)
    Inventories[id].items[slot].info.attachments[attachmentIndex] = nil
    cb(Inventories[id].items[slot].info.attachments or {})
end)

AddEventHandler('QBCore:Server:OnMoneyChange', function(src, moneyType, amount, type, reason)
    local id = formatInventoryId(src)

    if not Inventories[id] then return end

    print("Money change detected for inventory: " .. id .. ", type: " .. moneyType .. ", amount: " .. amount)

    TriggerClientEvent("inventory:cl:updateInventory", src, Inventories[id])
end)

QBCore.Functions.CreateCallback('weapons:server:ReloadWeapon', function(source, cb, ammo_type, ammo_amount)
    local src = source
    local ped = GetPlayerPed(src)
    local id = formatInventoryId(src)

    if not Inventories[id] then
        cb(0)
        return
    end

    local count, slots = GetItemCount(src, ammo_type)

    if count == 0 then return end

    if count > ammo_amount then
        RemoveItem(src, ammo_type, ammo_amount)
    else
        RemoveItem(src, ammo_type, count)
        cb(count)
    end

    cb(ammo_amount)
end)

--[[ FIN ATTACHMENTS ]]


--[[ TINTES ]]

for i = 0, 7 do
    QBCore.Functions.CreateUseableItem('weapontint_' .. i, function(source, item)
        EquipWeaponTint(source, i, item.name)
    end)
end

for i = 0, 32 do
    QBCore.Functions.CreateUseableItem('weapontint_mk2_' .. i, function(source, item)
        EquipWeaponTint(source, i, item.name)
    end)
end

function EquipWeaponTint(source, tint, name)
    if not source then return end
    local id = formatInventoryId(source)
    if not Inventories[id] then return end

    if tint > 7 and string.find(itemName, "mk2") == nil then
        TriggerClientEvent('QBCore:Notify', source, 'Este arma debe ser de tipo mk2', 'error')
        return
    end

    local slot = Inventories[id].current_weapon_slot

    if slot == nil then
        TriggerClientEvent('QBCore:Notify', source, 'Debes tener un arma equipada!', 'error')
        return
    end

    if Inventories[id].items[slot].info.tint == tint then
        TriggerClientEvent('QBCore:Notify', source, 'Ya tienes el arma pintada con este tine!', 'error')
        return
    end

    Inventories[id].items[slot].info.tint = tonumber(tint)

    TriggerClientEvent("inventory_client:EquipWeaponTint", source, tint)
    RemoveItem(source, name, 1)
end

--[[ FIN TINTES ]]

RegisterNetEvent("inventory:setcurrentWeaponSlot", function(slot)
    local src = source
    local id = formatInventoryId(src)

    if not Inventories[id] then return end

    if slot == nil then
        Inventories[id].current_weapon_slot = nil
        return
    end

    if Inventories[id].items[slot].type ~= "weapon" then
        Inventories[id].current_weapon_slot = nil
        return
    end

    Inventories[id].current_weapon_slot = slot
end)

RegisterNetEvent("inventory:updateWeaponAmmo", function(slot, ammo)
    local src = source
    local id = formatInventoryId(src)

    if not Inventories[id] then return end
    if not Inventories[id].items[slot] then return end

    Inventories[id].items[slot].info.ammo = ammo
    --saveInventory(id)
end)

RegisterNetEvent("inventory:unloadWeaponAmmo", function(slot, name, amount)
    local src = source
    local id = formatInventoryId(src)

    if not Inventories[id] then return end
    if not Inventories[id].items[slot] then return end
    if Inventories[id].items[slot].info.ammo < amount then return end

    Inventories[id].items[slot].info.ammo = 0

    AddItem(src, name, amount)
end)

RegisterNetEvent("inventory:setOpenState", function(id, state)
    if id == nil then
        local src = source
        id = formatInventoryId(src)
    else
        id = formatInventoryId(id)
    end

    if Inventories[id] == nil then return end
    Inventories[id].open = state
end)

RegisterNetEvent("inventory:swapItem", function(fromId, toId, fromSlot, toSlot, fromAmount, toAmount, secondInv)
    local src = source
    swapItem(fromId, toId, fromSlot, toSlot, fromAmount, toAmount, src, secondInv)
end)

RegisterNetEvent("inventory:server:RobPlayer", function(target)
    local src = source
    local player_inv = formatInventoryId(src)
    local other_id = formatInventoryId(target)

    if not Inventories[other_id] then return end
    if not Inventories[player_inv] then return end

    TriggerEvent("inventory:setOpenState", other_id, true)
    TriggerClientEvent("inventory:cl:OpenInventory", src, nil, Inventories[player_inv], Inventories[other_id])
end)

RegisterNetEvent("inventory:server:GiveItem", function(target, name, amount, slot)
    local src = source
    local player_inv = formatInventoryId(src)
    local other_id = formatInventoryId(target)

    if not Inventories[other_id] then return end
    if not Inventories[player_inv] then return end
    if not Inventories[player_inv].items[slot] then return end
    if not Inventories[player_inv].items[slot].name == name then return end

    local sameAmount = Inventories[player_inv].items[slot].amount >= amount
    if not sameAmount then return end

    AddItem(target, name, amount, nil, Inventories[player_inv].items[slot].info)
    RemoveItem(src, name, amount, slot)

    TriggerClientEvent("inventory:cl:updateInventory", target, Inventories[other_id])
    TriggerClientEvent("inventory:cl:updateInventory", src, Inventories[player_inv])
end)

RegisterNetEvent('inventory:server:OpenInventory', function(name, id, other)
    local src = source
    OpenInventory(name, id, other, src)
end)

-- QBCore needs 
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "RemoveItem", function(item, amount, slot)
        return RemoveItem(Player.PlayerData.source, item, amount, slot)
    end)

    QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "AddItem", function(item, amount, slot, info)
        return AddItem(Player.PlayerData.source, item, amount, slot, info)
    end)

    QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemByName", function(item)
        return GetItemByName(Player.PlayerData.source, item)
    end)

    QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetInventoryWeigth", function()
        return GetInventoryWeigth(Player.PlayerData.source)
    end)

    QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemsByName", function(item)
        return GetItemsByName(Player.PlayerData.source, item)
    end)

    -- updating drops for new player
    TriggerClientEvent("inventory_client:getDrops", Player.PlayerData.source, getDropInventories())
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        for k, v in pairs(Inventories) do
            saveInventory(k)
        end
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local Players = QBCore.Functions.GetQBPlayers()

    for k in pairs(Players) do
        local id = formatInventoryId(k)

        if not Inventories[id] then
            LoadInventory(id)
            Wait(250)
            Inventories[id].current_weapon_slot = nil
        end

        QBCore.Functions.AddPlayerMethod(k, "RemoveItem", function(item, amount, slot)
            return RemoveItem(k, item, amount, slot)
        end)

        QBCore.Functions.AddPlayerMethod(k, "AddItem", function(item, amount, slot, info)
            return AddItem(k, item, amount, slot, info)
        end)

        QBCore.Functions.AddPlayerMethod(k, "GetInventoryWeigth", function()
            return GetInventoryWeigth(k)
        end)

        QBCore.Functions.AddPlayerMethod(k, "GetItemsByName", function(item)
            return GetItemsByName(k, item)
        end)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local player_citizenid = Player.PlayerData.citizenid

    if not player_citizenid then return end

    local id = player_citizenid .. "-player"

    if not Inventories[id] then return end
    
    Inventories[id].current_weapon_slot = nil
    Inventories[id].open = false
    saveInventory(id)
    Inventories[id] = nil
end)

RegisterNetEvent("inventory:save", function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local player_citizenid = Player.PlayerData.citizenid

    if not player_citizenid then return end

    local id = player_citizenid .. "-player"
    saveInventory(id)
end)

--[[ COMMANDS ]]
QBCore.Commands.Add('giveitem', 'Give An Item (Admin Only)',
    { { name = 'id', help = 'Player ID' }, { name = 'item', help = 'Name of the item (not a label)' }, { name = 'amount', help = 'Amount of items' } },
    false, function(source, args)
        local src = source
        local id = formatInventoryId(args[1])
        local Player = nil

        if Inventories[id].type == "player" then
            Player = QBCore.Functions.GetPlayer(tonumber(args[1]))
        end

        local item_name = args[2]
        local amount = tonumber(args[3])

        if not QBCore.Shared.Items[item_name] then
            QBCore.Functions.Notify(src, "No existe este item...", 'error')
            return
        end
        
        local item_weight = QBCore.Shared.Items[item_name].weight * amount
        local item_info = nil

        if not Inventories[id] or not item_name or not amount then return end

        if (GetInventoryWeigth(id) + item_weight) > Inventories[id].maxweight then
            QBCore.Functions.Notify(src, "Parece que pesa demasiado para llevar esto...", 'error')
            return
        end

        local info = {}

        if item_name == 'id_card' then
            info.citizenid = Player.PlayerData.citizenid
            info.firstname = Player.PlayerData.charinfo.firstname
            info.lastname = Player.PlayerData.charinfo.lastname
            info.birthdate = Player.PlayerData.charinfo.birthdate
            info.gender = Player.PlayerData.charinfo.gender
            info.nationality = Player.PlayerData.charinfo.nationality
        elseif item_name == 'driver_license' then
            info.firstname = Player.PlayerData.charinfo.firstname
            info.lastname = Player.PlayerData.charinfo.lastname
            info.birthdate = Player.PlayerData.charinfo.birthdate
            info.type = 'Class C Driver License'
        elseif item_name == 'harness' then
            info.uses = 20
        end


        if AddItem(id, item_name, amount, false, info) then
            QBCore.Functions.Notify(source, 'You give x' .. tostring(amount) .. ' ' ..
                item_name .. ' to id ' .. tostring(args[1]), 'success')
        end

        --saveInventory(id)
        TriggerClientEvent("inventory:cl:updateInventory", src, Inventories[id])
    end, 'admin')

--- EXPORTS
exports("GetUsableItem", GetUsableItem)
exports("UseItem", UseItem)
exports('OpenInventory', OpenInventory)
exports('RemoveItem', RemoveItem)
exports("AddItem", AddItem)
exports('LoadInventory', LoadInventory)
exports('SaveInventory', saveInventory)
exports('GetItemByName', GetItemByName)
exports('HasItem', HasItem)
exports('GetItemsByName', GetItemsByName)
exports('GetItemCount', GetItemCount)
exports('GetInventory', GetInventory)
