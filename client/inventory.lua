local Inventories = {}
local CurrentDrop = nil
local currentWeapon = nil
local currentWeaponSlot = nil
local secondInv = nil
local QBCore = exports['qb-core']:GetCoreObject()
local inventarioAbierto = false


CreateThread(function()
    SetWeaponsNoAutoswap(true)
end)

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

RegisterNetEvent("inventory_client:getDrops", function(drops)
    for k, v in pairs(drops) do
        Inventories[v.id] = {
            id = v.id,
            coords = v.coords
        }
    end
end)

RegisterNetEvent("inventory:cl:createDropItem", function(id, coords)
    Inventories[id] = {
        id = id,
        coords = coords
    }

    secondInv = id
end)

RegisterNetEvent("inventory:cl:removeDropItem", function(id)
    Inventories[id] = nil
end)

RegisterNetEvent("inventory:cl:updateInventory", function(inventory, otherinventory)
    SendNUIMessage({
        action = 'update',
        id = inventory.id,
        inventory = inventory.items,
        weight = inventory.weight,
        maxweight = inventory.maxweight,
        slots = inventory.slots,
        other = otherinventory,
        error = isError,
    })
end)

RegisterNetEvent('inventory:cl:OpenInventory', function(PlayerAmmo, inventory, other)
    if not IsEntityDead(PlayerPedId()) then
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'open',
            inventory = inventory.items,
            id = inventory.id,
            type = inventory.type,
            slots = inventory.slots,
            other = other,
            weight = inventory.weight,
            maxweight = inventory.maxweight,
            maxammo = Config.MaximumAmmoValues,
        })
        inventarioAbierto = true
    end
end)

function loadAnimDict( dict )
	while ( not HasAnimDictLoaded( dict ) ) do
		RequestAnimDict( dict )
		Citizen.Wait( 0 )
	end
end

RegisterNetEvent('inventory_client:UseWeapon', function(weaponData, shootbool)
    local ped = PlayerPedId()
    local weaponName = tostring(weaponData.name)
    local weaponHash = joaat(weaponData.name)

    loadAnimDict( "reaction@intimidation@1h" )
    loadAnimDict( "weapons@pistol_1h@gang" )


    if currentWeapon == weaponName then
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        RemoveAllPedWeapons(ped, true)
        currentWeapon = nil
        currentWeaponSlot = nil
        TriggerServerEvent("inventory:setcurrentWeaponSlot", currentWeaponSlot)

        TaskPlayAnim(ped, "reaction@intimidation@1h", "outro", 10.0, 1.0, -1, 48, 2, 0, 0, 0)

    else
        if weaponData.name ~= currentWeapon and currentWeapon ~= nil then return end
        if weaponData.slot ~= currentWeaponSlot ~= weaponData.slot and currentWeaponSlot ~= nil then return end

        TaskPlayAnim(ped, "reaction@intimidation@1h", "intro", 10.0, 1.0, -1, 48, 2, 0, 0, 0)

        local ammo = tonumber(weaponData.info.ammo) or 0

        GiveWeaponToPed(ped, weaponHash, ammo, false, false)
        SetPedAmmo(ped, weaponHash, ammo)
        SetCurrentPedWeapon(ped, weaponHash, true)

        if weaponData.info.attachments then
            for _, attachment in pairs(weaponData.info.attachments) do
                GiveWeaponComponentToPed(ped, weaponHash, joaat(attachment.component))
            end
        end

        if weaponData.info.tint then
            SetPedWeaponTintIndex(ped, weaponHash, weaponData.info.tint)
        end

        currentWeapon = weaponName
        currentWeaponSlot = weaponData.slot
        TriggerServerEvent("inventory:setcurrentWeaponSlot", currentWeaponSlot)

        CreateThread(function()
            while currentWeapon ~= nil do
                local playerPed = PlayerPedId()
                local weapon = GetSelectedPedWeapon(ped)
                local ammo = GetAmmoInPedWeapon(ped, weapon)

                -- Checking if player is shooting and updating ammo
                if (IsControlJustReleased(0, 24) or IsDisabledControlJustReleased(0, 24)) then
                    TriggerServerEvent("inventory:updateWeaponAmmo", weaponData.slot, ammo)
                end

                -- Reloading weapon with 'R' key
                if IsControlJustPressed(1, 45) then
                    local clip_ammo = GetMaxAmmoInClip(playerPed, currentWeapon, false)
                    local ammo_diff = clip_ammo - ammo

                    if ammo < clip_ammo then
                        QBCore.Functions.TriggerCallback('weapons:server:ReloadWeapon', function(reloaded)
                            SetPedAmmo(PlayerPedId(), currentWeapon, 0)
                            SetPedAmmo(PlayerPedId(), currentWeapon, ammo + reloaded)
                            ammo = GetAmmoInPedWeapon(ped, weapon)

                            TriggerServerEvent("inventory:updateWeaponAmmo", weaponData.slot, ammo)
                        end, Config.WeaponAmmoByGroup[GetWeapontypeGroup(currentWeapon)], ammo_diff)
                    else
                        QBCore.Functions.Notify('El arma ya esta cargada!!', 'error')
                    end
                end
                Wait(5)
            end
        end)
    end
end)

function HasItem(item, amount)
    local p = promise.new()
    QBCore.Functions.TriggerCallback('inventory:server:HasItem', function(bool)
        p:resolve(bool)
    end, item, amount)
    return Citizen.Await(p)
end

exports('HasItem', HasItem)

function HowMuchItems(item)
    local p = promise.new()
    QBCore.Functions.TriggerCallback('inventory:server:HowMuchItems', function(amount, slots, bag)
        p:resolve(amount)
    end, item)
    return Citizen.Await(p)
end

exports('HowMuchItems', HowMuchItems)

function getUserInventory()
    local p = promise.new()
    QBCore.Functions.TriggerCallback('inventory:server:GetInventory', function(inventory)
        p:resolve(inventory)
    end)
    return Citizen.Await(p)
end

exports("getUserInventory", getUserInventory)

RegisterNetEvent("inventory_client:EquipWeaponTint", function(tint)
    local ped = PlayerPedId()
    local pistola, hash = GetCurrentPedWeapon(ped, false)
    if not hash then return end
    SetPedWeaponTintIndex(ped, hash, tint)
end)

local function closeInventory()
    if CurrentDrop ~= nil then
        TriggerServerEvent("inventory:setOpenState", CurrentDrop, false)
    end

    if secondInv ~= nil then
        TriggerServerEvent("inventory:setOpenState", secondInv, false)
    end

    TriggerServerEvent("inventory:setOpenState", nil, false)
    inventarioAbierto = false
end

for i = 1, 6 do
    RegisterCommand('slot' .. i, function()
        if i == 6 then
            i = Config.MaxInventorySlots
        end
        if currentWeaponSlot ~= nil and currentWeaponSlot ~= i then return end
        TriggerServerEvent('inventory:server:UseItemSlot', i)
        closeInventory()
    end, false)
    RegisterKeyMapping('slot' .. i, Lang:t('inf_mapping.use_item') .. i, 'keyboard', i)
end

RegisterNetEvent("inventory_client:setSecondInv", function(inv)
    secondInv = inv
end)

RegisterCommand('inventory', function()
    if IsNuiFocused() then return end
    if inventarioAbierto then
        TriggerEvent('inventory:cl:closeInventory')
    elseif not QBCore.Functions.GetPlayerData().metadata['isdead'] and not QBCore.Functions.GetPlayerData().metadata['inlaststand'] and not QBCore.Functions.GetPlayerData().metadata['ishandcuffed'] and not IsPauseMenuActive() then
        local ped = PlayerPedId()

        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            secondInv = GetVehicleNumberPlateText(vehicle)

            TriggerServerEvent('inventory:server:OpenInventory', 'glovebox', secondInv, {
                maxweight = Config.MaxGloveboxWeight,
                slots = Config.MaxGloveboxSlots,
            })

            secondInv = secondInv .. "-glovebox"
        else
            secondInv = nil

            local nearVehicle = QBCore.Functions.GetClosestVehicle()
            local nearVehicleCoords = GetEntityCoords(nearVehicle)
            local vehicleDistance = #(nearVehicleCoords - GetEntityCoords(ped))

            if vehicleDistance < 2.5 then
                if GetVehicleDoorLockStatus(nearVehicle) < 2 then
                    secondInv = QBCore.Functions.GetPlate(nearVehicle)
                    local vehicleClass = GetVehicleClass(nearVehicle)

                    if not vehicleClass then
                        vehicleClass = 'default'
                    end

                    --[[ Aqui config slots de trunk ]]
                    local other = {
                        maxweight = Config.TrunkSpace[vehicleClass].maxWeight,
                        slots = Config.TrunkSpace[vehicleClass].slots,
                    }

                    TriggerServerEvent('inventory:server:OpenInventory', 'trunk', secondInv, other)
                    secondInv = secondInv .. "-trunk"
                else
                    secondInv = nil
                    TriggerServerEvent('inventory:server:OpenInventory', nil, CurrentDrop)
                end
            else
                secondInv = nil
                TriggerServerEvent('inventory:server:OpenInventory', nil, CurrentDrop)
            end
        end
    end
end, false)

-- DROP SYSTEM
CreateThread(function()
    local sleep = 1000
    while true do
        Wait(sleep)
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        if not Inventories[CurrentDrop] then
            CurrentDrop = 0
        end

        for index, item in pairs(Inventories) do
            if item.coords ~= nil then
                local distance = #(coords - item.coords)
                if distance < 2.5 then
                    sleep = 0
                    DrawMarker(20, item.coords.x, item.coords.y, item.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3,
                        0.15, 120, 10, 20, 155, false, false, false, 1, false, false, false)
                    CurrentDrop = item.id
                    secondInv = item.id
                else
                    CurrentDrop = 0
                    secondInv = nil
                end
            end
        end
    end
end)

-- USO DE ITEMS

RegisterNetEvent('inventory_client:CheckWeapon', function(weaponName)
    if currentWeapon ~= weaponName:lower() then return end
    local ped = PlayerPedId()
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    RemoveAllPedWeapons(ped, true)
    currentWeapon = nil
    currentWeaponSlot = nil
    TriggerServerEvent("inventory:setcurrentWeaponSlot", currentWeaponSlot)
end)

RegisterNetEvent("inventory:cl:closeInventory", function()
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'close',
    })
    closeInventory()
end)

RegisterCommand("robar", function()
    local player, distance = QBCore.Functions.GetClosestPlayer(GetEntityCoords(PlayerPedId()))
    if player ~= -1 and distance < 3 then
        secondInv = GetPlayerServerId(player)
        TriggerServerEvent('inventory:server:RobPlayer', GetPlayerServerId(player))
    else
        QBCore.Functions.Notify(Lang:t('notify.nonb'), 'error')
    end
end)

--[[ Callbacks ]]
RegisterNUICallback('RemoveAttachment', function(data, cb)
    local ped = PlayerPedId()
    QBCore.Functions.TriggerCallback('weapons:server:RemoveAttachment', function(NewAttachments)
    end, data.itemslot, data.attachment)
end)

RegisterNuiCallback("unloadWeaponAmmo", function(data, cb)
    if currentWeapon ~= nil then
        SetPedAmmo(PlayerPedId(), currentWeapon, 0)
    end

    local weapon_group = GetWeapontypeGroup(GetHashKey(data.name))
    local ammo_type = Config.WeaponAmmoByGroup[weapon_group]
    TriggerServerEvent("inventory:unloadWeaponAmmo", data.slot, ammo_type, data.amount)
end)

RegisterNUICallback('CloseInventory', function(_, cb)
    SetNuiFocus(false, false)
    closeInventory()
    cb('ok')
end)

RegisterNUICallback('UseItem', function(data, cb)
    TriggerServerEvent('inventory:server:UseItem', data.inventory, data.item)
    cb('ok')
end)

RegisterNUICallback('SetInventoryData', function(data, cb)
    TriggerServerEvent("inventory:swapItem", data.fromInventory, data.toInventory, data.fromSlot, data.toSlot,
        data.fromAmount, data.toAmount, secondInv)
    cb('ok')
end)

RegisterNUICallback('GiveItem', function(data, cb)
    local player, distance = QBCore.Functions.GetClosestPlayer(GetEntityCoords(PlayerPedId()))
    if player ~= -1 and distance < 3 then
        local inventory_data = splitString(data.inventory, "-")
        if inventory_data[2] == "player" then
            TriggerServerEvent('inventory:server:GiveItem', GetPlayerServerId(player), data.item.name, data.amount,
                data.item.slot)
        end
    else
        QBCore.Functions.Notify(Lang:t('notify.nonb'), 'error')
    end
    cb('ok')
end)

--[[ MAPPING KEYS ]]
RegisterKeyMapping('inventory', Lang:t('inf_mapping.opn_inv'), 'keyboard', Config.KeyBinds.Inventory)
