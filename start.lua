local monitor = peripheral.wrap("right")
local monitor_2 = peripheral.wrap("monitor_0")
local scroll_window = nil
local path = "crafts.json"
local w, h = 0, 0
local data = {}
local itemKeys = {}
local scrollOffset = 0 -- На сколько строк мы пролистали вниз
local multipliers = {1, 4, 8, 16, 24, 32, 40, 48, 56, 64}
local maxCols = 5      -- Сколько кнопок в одном ряду
local btnWidth = 2     -- Ширина кнопки (текста)
local paddingX = 3 
local paddingY = 1     -- Расстояние между кнопками по вертикали
local winX, winY = 3, 18 -- Координаты верхнего левого угла окна с кнопками количества
local selectedItem = nil -- Выбранный предмет для крафта
local currentRecipeType = "crafting"
local selectedProcessInterface = nil
local selectedProcessOutputSlots = {}
local processSelectionActive = false
local processCandidates = {}
local barrel = peripheral.wrap("minecraft:barrel_0")
local barrel_name = "minecraft:barrel_0"



-- Функция получения всех устройств (если нужно)
local function getAllDevices()
    local allDevices = peripheral.getNames()
    return allDevices
end

local function isProcessInterface(name)
    local pType = peripheral.getType(name) or ""
    if name == barrel_name then
        return false
    end
    if pType == "turtle" then
        return false
    end
    local device = peripheral.wrap(name)
    return device and device.pushItems and device.pullItems
end

local function getProcessInterfaces()
    local interfaces = {}
    for _, name in ipairs(getAllDevices()) do
        if isProcessInterface(name) then
            local pType = peripheral.getType(name) or "unknown"
            table.insert(interfaces, { name = name, type = pType })
        end
    end
    return interfaces
end

local function getInterfaceContents(name)
    local device = peripheral.wrap(name)
    if not device or not device.list then
        return {}
    end
    local items = {}
    local success, result = pcall(device.list)
    if success and result then
        for slot, item in pairs(result) do
            items[slot] = item
        end
    end
    return items
end

local function getInterfaceItemCount(name, itemName)
    local total = 0
    for _, item in pairs(getInterfaceContents(name)) do
        if item.name == itemName then
            total = total + item.count
        end
    end
    return total
end

local function drawProcessSelection()
    processSelectionActive = true
    win_count_craft.setBackgroundColour(colors.black)
    win_count_craft.clear()
    win_count_craft.setCursorPos(1,1)
    win_count_craft.setTextColour(colors.white)
    win_count_craft.write("Select process interface")

    scroll_window.setBackgroundColour(colors.black)
    scroll_window.clear()
    scroll_window.setTextColour(colors.white)
    for i, entry in ipairs(processCandidates) do
        if i > 11 then break end
        scroll_window.setCursorPos(1, i)
        local label = i .. ". " .. entry.name .. " [" .. entry.type .. "]"
        scroll_window.write(label:sub(1, 57))
    end
end

local function getPatternFromInterface(name)
    local device = peripheral.wrap(name)
    if device and device.list then
        local inv = device.list()
        local pattern = {}
        for slot = 1, 9 do
            local item = inv[slot]
            if item then
                pattern[slot] = item.name
            else
                pattern[slot] = " "
            end
        end
        return pattern
    end
    return {}
end

local function detectOutputSlots(name, before, outputName)
    local after = getInterfaceContents(name)
    local outputSlots = {}
    for slot, item in pairs(after) do
        if item and item.name == outputName then
            if not before[slot] or before[slot].name ~= outputName or item.count > before[slot].count then
                table.insert(outputSlots, slot)
            end
        end
    end
    return outputSlots
end

local function getBarrelPattern()
    local inv = barrel.list()
    local pattern = {}
    local slots = {4, 5, 6, 13, 14, 15, 22, 23, 24}
    for i = 1, 9 do
        local item = inv[slots[i]]
        if item then
            pattern[i] = item.name
        else
            pattern[i] = " "
        end
    end
    return pattern
end

local function pushBarrelPatternToInterface(interfaceName)
    local sourceSlots = {4, 5, 6, 13, 14, 15, 22, 23, 24}
    local totalMoved = 0
    for _, slot in ipairs(sourceSlots) do
        local item = barrel.getItemDetail(slot)
        if item and item.count > 0 then
            local moved = barrel.pushItems(interfaceName, slot, item.count)
            totalMoved = totalMoved + moved
        end
    end
    return totalMoved
end

local function waitForProcessOutput(interfaceName, outputName, expectedCount, timeout)
    local device = peripheral.wrap(interfaceName)
    if not device then
        return false
    end
    local startTime = os.clock()
    local lastCount = getInterfaceItemCount(interfaceName, outputName)
    local stableTicks = 0
    while os.clock() - startTime < timeout do
        os.sleep(0.5)
        local currentCount = getInterfaceItemCount(interfaceName, outputName)
        local meetsExpected = true
        if expectedCount then
            meetsExpected = currentCount >= expectedCount
        end
        if meetsExpected and currentCount == lastCount then
            stableTicks = stableTicks + 1
        else
            stableTicks = 0
        end
        lastCount = currentCount
        if stableTicks >= 2 and currentCount > 0 then
            return true
        end
    end
    return false
end

-- Функция инициализации монитора
local function initMonitor()
    monitor.setBackgroundColour(colors.black)
    monitor.clear()
    monitor.setTextScale(1)
    w, h = monitor.getSize()
    print(w, h)
end

local function initTurtle()
    -- Инициализация черепахи (если нужно)
    turtle = peripheral.wrap("turtle_0")
end

-- Функция создания окна прокрутки
local function createScrollWindow()
    choiseadd_window = window.create(monitor, 3, 7, 78, 16)
    choiseadd_window.setBackgroundColour(colors.gray)
    choise_window = window.create(monitor, 3, 7, 78, 16)
    choise_window.setBackgroundColour(colors.gray)
    scroll_window = window.create(monitor, 3, 7, 78, 16)
    scroll_window.setBackgroundColour(colors.gray)
    win_count_craft = window.create(monitor, 3, 7, 78, 16)
    win_count_craft.setBackgroundColour(colors.gray)
end

local function initStorages()
    storages = {}
    local allDevices = getAllDevices()
    for i, name in ipairs(allDevices) do
        if string.sub(name,1,17) == "create:item_vault" then
            local storage = peripheral.wrap(name)
            table.insert(storages, {
                name = name,
                peripheral = storage,
                type = "create_vault"
            })
            print("Item_vault found")
        end
    end
    print("Found " .. #storages .. " item_vaults")

end

-- Получение всех предметов из хранилища (работает надёжно)
local function getAllItemsFromStorage(storagePeripheral)
    local items = {}
    -- Исправленный вызов list(): убран лишний аргумент storagePeripheral
    if storagePeripheral.list then
        local success, result = pcall(storagePeripheral.list) 
        if success and result then
            return result
        end
    end
    
    -- Резервный перебор слотов с увеличенным лимитом для больших Vaults
    local size = 1000 
    if storagePeripheral.size then
        local success, s = pcall(storagePeripheral.size)
        if success then size = s end
    end
    
    for slot = 1, size do
        local item = storagePeripheral.getItemDetail(slot)
        if item then
            items[slot] = item
        end
    end
    return items
end

-- Исправленная findItemInStorages
local function findItemInStorages(itemId, count)
    count = count or 1
    
    -- СНАЧАЛА проверяем бочку (промежуточные крафты)
    for i = 1, 27 do
        local item = barrel.getItemDetail(i)
        if item and item.name == itemId then
            if item.count >= count then
                return { name = barrel_name, peripheral = barrel, type = "barrel" }, i, item
            end
        end
    end

    -- ЗАТЕМ проверяем хранилища
    for _, storage in ipairs(storages) do
        local items = getAllItemsFromStorage(storage.peripheral)
        for slot, item in pairs(items) do
            if item.name == itemId and item.count >= count then
                return storage, slot, item
            end
        end
    end
    return nil, nil, nil
end

local function takeFromStorage(itemId, count, targetSlot)
    local storage, slot, item = findItemInStorages(itemId, count)
    if storage then
        local takeCount = math.min(count, item.count)
        storage.peripheral.pushItems(barrel_name, slot, takeCount, targetSlot)
        print("Taked " .. takeCount .. " x " .. itemId)
        return true
    end
    
    print("Not found: " .. itemId)
    return false
end


local function clearBarrelToStorage()
    local totalMoved = 0
    if not barrel then
        print("Barrel not found")
        return false
    end
    for i = 1, 27 do
        local item = barrel.getItemDetail(i)
        if item and item.count > 0 then
            local moved = false

            for _, storage in ipairs(storages) do
                local result = barrel.pushItems(storage.name, i, item.count)
                if result > 0 then
                    totalMoved = totalMoved + result
                    print("Transfered " .. result .. " x " .. item.name .. " in " .. storage.name)
                    moved = true
                    break  -- Предмет перемещен, выходим из цикла по хранилищам
                end
            end
            if not moved then
                print("Fail transfer " .. item.name .. " (storage full)")
            end
        end
    end
end


local function initMonitor_2()
    monitor_2.setBackgroundColour(colors.black)
    monitor_2.clear()
    local w, h = monitor_2.getSize()
    monitor_2.setBackgroundColour(colors.gray)
    monitor_2.setCursorPos(1, h/2+1)
    monitor_2.write("Push >>")
end


local function btn_clear()
    selectedItem = nil
    displayRecipes()
    win_count_craft.setBackgroundColour(colors.black)
    win_count_craft.clear()
end


-- Функция загрузки рецептов из JSON
local function loadRecipes()
    if fs.exists(path) then
        local file = fs.open(path, "r")
        local content = file.readAll()
        file.close()
        data = textutils.unserializeJSON(content)
        return data
    else
        print("File not found")
        data = {}
        return data
    end
end

-- Функция отображения рецептов в окне
local function displayRecipes()
    scroll_window.setBackgroundColour(colors.black)
    scroll_window.clear()
    
    local winW, winH = scroll_window.getSize()
    for i = 1, winH do
        local index = i + scrollOffset
        local itemId = itemKeys[index]
        
        if itemId then
            scroll_window.setCursorPos(1, i)
            if itemId == selectedItem then
                scroll_window.setBackgroundColour(colors.blue)
                scroll_window.setTextColour(colors.white)
            else
                scroll_window.setBackgroundColour(colors.gray)
                scroll_window.setTextColour(colors.white)
            end
            local label = itemId:sub(1, winW)
            scroll_window.write(label .. string.rep(" ", winW - #label))
        end
    end
end


local function updateItemKeys()
    itemKeys = {}
    for name, _ in pairs(data) do
        print(name, _)
        table.insert(itemKeys, name)
    end
    table.sort(itemKeys) -- Сортируем по алфавиту
    for i, name in ipairs(itemKeys) do
        print(name)
    end
end

-- Функция рисования кнопки ADD
local function drawAddButton()
    btnX_add = 4  -- X позиция кнопки
    btnY_add = 22  -- Y позиция кнопки
    
    monitor.setBackgroundColour(colors.lime)
    
    -- Рисуем кнопку 3 строки высотой и 8 символов шириной
    for y = btnY_add, btnY_add + 2 do
        monitor.setCursorPos(btnX_add, y)
        monitor.write(string.rep(" ", 8))
    end
    
    -- Пишем текст ADD по центру кнопки
    monitor.setCursorPos(btnX_add + 2, btnY_add + 1)
    monitor.write("ADD")
end

-- Функция рисования горизонтальной линии
local function drawHorizontalLine()
    -- for x = 0, w do
    --     monitor.setBackgroundColour(colors.gray)
    --     monitor.setCursorPos(x, h/2+3)
    --     monitor.write(" ")
    -- end
    -- monitor.setCursorPos(3, h/2+3)
    -- monitor.write("<<  >>")

    for x = 0, w do
        monitor.setBackgroundColour(colors.yellow)
        monitor.setCursorPos(x, 26)
        monitor.write(" ")
    end
end

-- Функция рисования вертикальной линии
local function drawVerticalLine()
    monitor.setCursorPos(1, 1)
    for i = 2, h do
        monitor.setBackgroundColour(colors.yellow)
        monitor.write(" ")
        monitor.setCursorPos(1, i)
    end
    for i = 2, h do
        monitor.setBackgroundColour(colors.yellow)
        monitor.write(" ")
        monitor.setCursorPos(82, i)
    end
end

-- Функция рисования горизонтальной линии вверху
local function drawTopHorizontalLine()
    monitor.setCursorPos(1, 1)
    for i = 0, w do
        monitor.setBackgroundColour(colors.yellow)
        monitor.write(" ")
        if i == w then
            break
        end
    end
end

-- Функция настройки заголовка окна
local function setupWindowHeader()
    monitor.setCursorPos(3, 3)
    monitor.setBackgroundColour(colors.gray)
    monitor.write("Items avable")
end


local function btn_add()
    if btn_add_choise then
        return
    end

    -- 1. СБРОС: Убираем выделение предмета и режимы
    selectedItem = nil
    currentRecipeType = "crafting"
    selectedProcessInterface = nil
    selectedProcessOutputSlots = {}
    processSelectionActive = false
    processCandidates = {}
    displayRecipes() -- список снова станет просто серым

    -- 2. ОЧИСТКА: Убираем кнопки x1, x4... если они были
    win_count_craft.setBackgroundColour(colors.black)
    win_count_craft.clear()

    -- 3. Теперь рисуем меню ADD
    choise_window.setBackgroundColour(colors.gray)
    choise_window.setCursorPos(1,1)
    choise_window.write("Craft")
    choise_window.setCursorPos(7, 1)
    choise_window.write("Process")
end


function saveConfig(data)
    local file = fs.open(path, "w")
    
    local jsonString = "{"
    local first = true
    
    for itemId, recipe in pairs(data) do
        if not first then
            jsonString = jsonString .. ","
        end
        first = false
        
        jsonString = jsonString .. '\n  "' .. itemId .. '": {'
        jsonString = jsonString .. '\n    "type": "' .. recipe.type .. '",'
        jsonString = jsonString .. '\n    "craft": ' .. recipe.craft .. ','
        jsonString = jsonString .. '\n    "machine": "' .. recipe.machine .. '",'
        if recipe.outputSlots and #recipe.outputSlots > 0 then
            jsonString = jsonString .. '\n    "outputSlots": ['
            for i = 1, #recipe.outputSlots do
                jsonString = jsonString .. '\n      ' .. recipe.outputSlots[i]
                if i < #recipe.outputSlots then
                    jsonString = jsonString .. ","
                end
            end
            jsonString = jsonString .. '\n    ],'
        end
        jsonString = jsonString .. '\n    "pattern": ['
        
        for i = 1, 9 do
            local patternItem = recipe.pattern[i] or " "
            jsonString = jsonString .. '\n      "' .. patternItem .. '"'
            if i < 9 then
                jsonString = jsonString .. ","
            end
        end
        
        jsonString = jsonString .. '\n    ]'
        jsonString = jsonString .. '\n  }'
    end
    
    jsonString = jsonString .. "\n}"
    
    file.write(jsonString)
    file.close()
end


function getPatternFromBarrel()
    local inv = barrel.list()
    local pattern = {}
    -- Координаты слотов в бочке, которые имитируют сетку 3х3
    local slots = {4, 5, 6, 13, 14, 15, 22, 23, 24}
    
    for i = 1, 9 do
        local item = inv[slots[i]]
        if item then
            pattern[i] = item.name -- Записываем ID предмета
        else
            pattern[i] = " " -- Твой формат для пустых слотов
        end
    end
    return pattern
end


function addCraft(resultName, count, pattern)
    if resultName == "" then
        print("Result name cannot be empty")
        return
    end
    data = loadRecipes() -- Читаем старые данные
    if data[resultName] then
        print("Recipe for " .. resultName .. " already exists!")
        return
    end

    local recipeType = currentRecipeType or "crafting"
    local recipeMachine = "crafting_table"
    if recipeType == "processing" and selectedProcessInterface then
        recipeMachine = selectedProcessInterface
    end

    data[resultName] = {
        type = recipeType,
        craft = count or 1,
        machine = recipeMachine,
        outputSlots = selectedProcessOutputSlots,
        pattern = pattern
    }
    
    saveConfig(data) -- Перезаписываем файл целиком
    print("Recipe for " .. resultName .. " successfully added!")
end



local function btn_addcraft()

    btn_add_choise = true
    choiseadd_window.setCursorPos(1,1)
    choiseadd_window.write("Whould you like to save this craft?")
    choiseadd_window.setBackgroundColour(colors.lime)
    choiseadd_window.setCursorPos(10,3)
    choiseadd_window.write("YES")
    choiseadd_window.setCursorPos(20,3)
    choiseadd_window.setBackgroundColour(colors.red)
    choiseadd_window.write("NO")

    if btn_add_choise then
        patternc = getPatternFromBarrel()

        if currentRecipeType == "processing" then
            if not selectedProcessInterface then
                print("No process interface selected")
                bf = false
                return
            end

            local before = getInterfaceContents(selectedProcessInterface)
            local transferred = pushBarrelPatternToInterface(selectedProcessInterface)
            print("Transferred " .. transferred .. " items to " .. selectedProcessInterface)

            if transferred == 0 then
                print("Nothing moved to process interface")
                bf = false
                return
            end

            -- Ждем, пока процесс не даст результат
            sleep(1)
            local after = getInterfaceContents(selectedProcessInterface)
            local resultCandidate = nil
            for slot, item in pairs(after) do
                if item and item.name then
                    local beforeCount = (before[slot] and before[slot].count) or 0
                    if item.count > beforeCount then
                        resultCandidate = item.name
                        break
                    end
                end
            end
            if not resultCandidate then
                for slot, item in pairs(after) do
                    if item and item.name and not before[slot] then
                        resultCandidate = item.name
                        break
                    end
                end
            end

            if not resultCandidate then
                print("Cannot detect process output")
                bf = false
                return
            end

            if not waitForProcessOutput(selectedProcessInterface, resultCandidate, nil, 10) then
                print("Process output not stable")
            end

            selectedProcessOutputSlots = detectOutputSlots(selectedProcessInterface, before, resultCandidate)
            selectedProcessOutputSlots = selectedProcessOutputSlots or {}

            local device = peripheral.wrap(selectedProcessInterface)
            craft_items = 0
            item_name = ""
            if device then
                for _, slot in ipairs(selectedProcessOutputSlots) do
                    local item = device.getItemDetail(slot)
                    if item then
                        device.pushItems(barrel_name, slot, item.count)
                        craft_items = craft_items + item.count
                        if item_name == "" then
                            item_name = item.name
                        end
                    end
                end
            end

            if item_name ~= "" then
                bf = true
                print("Process output detected: " .. item_name .. " x" .. craft_items)
            else
                bf = false
                print("No process output moved to barrel")
            end
        else
            local modem = peripheral.wrap("bottom")
            local channel = 1
            local turtleSlot = 1  -- Начинаем с 1-го слота черепашки
            
            for i = 1, 27 do
                if (i >= 4 and i < 7) or (i >= 13 and i < 16) or (i >= 22 and i < 25) then
                    if turtleSlot <= 16 then
                        if turtleSlot == 4 or turtleSlot == 8 then
                            turtleSlot = turtleSlot + 1
                        end
                        barrel.pushItems("turtle_0", i, 64, turtleSlot)
                        turtleSlot = turtleSlot + 1
                    end
                end
            end

            if next(barrel.list()) then
                bf = true
                print("Barrel has items")
            else
                bf = false
                print("Barrel is empty")
            end 

            local datac = {
                command = "craft",
                count = 64
            }

            modem.open(1)
            modem.transmit(channel, channel, datac)
            print("Command sent")

            for i = 1, 16 do
                barrel.pullItems("turtle_0", i, 64)
            end

            craft_items = 0
            item_name = ""
            for i = 1, 27 do
                local item = barrel.list()[i]
                if item then
                    craft_items = craft_items + item.count
                    if item_name == "" then
                        item_name = item.name
                    end
                end
            end
        end
    else
        print("Select another option")
    end

end


local function btn_addprocess()
    currentRecipeType = "processing"
    selectedProcessInterface = nil
    selectedProcessOutputSlots = {}
    processCandidates = getProcessInterfaces()

    if #processCandidates == 0 then
        win_count_craft.setBackgroundColour(colors.black)
        win_count_craft.clear()
        win_count_craft.setCursorPos(1,1)
        win_count_craft.setTextColour(colors.red)
        win_count_craft.write("No process interfaces found")
        return
    end

    drawProcessSelection()
end


local function btn_no()
    btn_add_choise = false
    choiseadd_window.setCursorPos(1,1)
    choiseadd_window.clear()
    choiseadd_window.setBackgroundColour(colors.black)
    choiseadd_window.setCursorPos(3,1)
    choiseadd_window.clear()
end



local function btn_yes()
    -- saveRecipe()
    if bf then
        addCraft(item_name, craft_items, patternc)

        btn_add_choise = false
        choiseadd_window.setCursorPos(1,1)
        choiseadd_window.clear()
        choiseadd_window.setBackgroundColour(colors.black)
        choiseadd_window.setCursorPos(3,1)
        choiseadd_window.clear()
        choiseadd_window.setBackgroundColour(colors.black)
        choiseadd_window.setCursorPos(10,3)
        choiseadd_window.setBackgroundColour(colors.gray)
        choiseadd_window.write("Craft saved")
        sleep(1)
        choiseadd_window.setBackgroundColour(colors.black)
        choiseadd_window.clear()
        choiseadd_window.setBackgroundColour(colors.black)
        print("Craft saved")
        updateItemKeys()
        displayRecipes()

    else 
        btn_add_choise = false
        choiseadd_window.setBackgroundColour(colors.black)
        choiseadd_window.setCursorPos(1,1)
        choiseadd_window.clear()
        choiseadd_window.setBackgroundColour(colors.black)
        choiseadd_window.setCursorPos(3,1)
        choiseadd_window.clear()
        choiseadd_window.setCursorPos(5,3)
        choiseadd_window.setBackgroundColour(colors.red)
        choiseadd_window.write("Craft not saved")
        sleep(1)
        choiseadd_window.setCursorPos(1,1)
        choiseadd_window.clear()
        choiseadd_window.setBackgroundColour(colors.black)
        choiseadd_window.setCursorPos(3,1)
        choiseadd_window.clear()
        print("Craft not saved, clear the barrel")
    end


end

local function scroll_left()
    scrollOffset = math.max(0, scrollOffset - 1)
    displayRecipes()
    print("Scroll left")
end

local function scroll_right()
    scrollOffset = math.min(#itemKeys - 11, scrollOffset + 1)
    displayRecipes()
    print("Scroll right")
end

local function drawQuantityButtons(itemName, baseCount)
    btn_add_choise = false
    btn_add_active = false
    
    win_count_craft.setBackgroundColour(colors.black)
    win_count_craft.clear()
    
    -- НАСТРОЙКИ СЕТКИ
    local paddingY = 1     -- Расстояние между кнопками по вертикали
    local startX = 1       -- Начальный отступ от края окна
    local startY = 1     -- Начальный отступ сверху

    for i, m in ipairs(multipliers) do
        local totalToCraft = baseCount * m
        
        -- ВЫЧИСЛЕНИЕ ПОЗИЦИИ (Магия математики)
        -- Порядковый номер в ряду (0, 1, 2)
        local column = (i - 1) % maxCols 
        -- Номер текущего ряда (0, 1, 2...)
        local row = math.floor((i - 1) / maxCols) 

        -- Финальные координаты
        local xPos = startX + (column * (btnWidth + paddingX))
        local yPos = startY + (row * (paddingY + 1)) -- +1 это высота самой кнопки

        -- ОТРИСОВКА
        win_count_craft.setCursorPos(xPos, yPos)
        win_count_craft.setBackgroundColour(colors.blue)
        win_count_craft.setTextColour(colors.white)
        
        -- Форматируем текст, чтобы кнопки были одинаковой ширины [ x128 ]
        local label = "x" .. totalToCraft
        win_count_craft.write(label .. string.rep(" ", btnWidth - #label))
    end
end

local function btn_count_craft()
    win_count_craft.setBackgroundColour(colors.gray)
    win_count_craft.setCursorPos(1,1)
end

local function btn_craft_choose(itemName)
    local recipe = data[itemName]
    if recipe then
        local count = recipe.craft

        drawQuantityButtons(itemName, count)
        print("Crafting " .. itemName .. " x" .. count)
    else
        print("Recipe not found for " .. itemName)
    end

end


local function pushIngredientsToProcessInterface(recipe, batches)
    local interfaceName = recipe.machine
    local device = peripheral.wrap(interfaceName)
    if not device then
        print("Error: process interface not found: " .. tostring(interfaceName))
        return false
    end

    for i = 1, 9 do
        local neededItem = recipe.pattern[i]
        if neededItem and neededItem ~= " " then
            local remaining = batches
            for _, storage in ipairs(storages) do
                if remaining <= 0 then break end
                local items = getAllItemsFromStorage(storage.peripheral)
                for slot, item in pairs(items) do
                    if item.name == neededItem and item.count > 0 then
                        local take = math.min(remaining, item.count)
                        local moved = storage.peripheral.pushItems(interfaceName, slot, take)
                        remaining = remaining - moved
                        if remaining <= 0 then break end
                    end
                end
            end
            if remaining > 0 then
                print("Error: missing " .. neededItem)
                return false
            end
        end
    end
    return true
end

local function retrieveProcessOutputs(recipe, before)
    local interfaceName = recipe.machine
    local device = peripheral.wrap(interfaceName)
    if not device then
        print("Error: process interface not found: " .. tostring(interfaceName))
        return false, nil, 0
    end

    local after = getInterfaceContents(interfaceName)
    local resultSlots = {}
    local resultName = nil

    if recipe.outputSlots and #recipe.outputSlots > 0 then
        for _, slot in ipairs(recipe.outputSlots) do
            table.insert(resultSlots, slot)
        end
    else
        for slot, item in pairs(after) do
            local beforeCount = (before[slot] and before[slot].count) or 0
            if item and item.count > beforeCount then
                table.insert(resultSlots, slot)
            end
        end
    end

    local totalCount = 0
    for _, slot in ipairs(resultSlots) do
        local item = device.getItemDetail(slot)
        if item then
            local moved = device.pushItems(barrel_name, slot, item.count)
            if moved > 0 then
                totalCount = totalCount + moved
                resultName = resultName or item.name
            end
        end
    end

    return totalCount > 0, resultName, totalCount
end

local function waitForProcessCompletion(interfaceName, before, outputSlots, timeout)
    local startTime = os.clock()
    local stableTicks = 0
    local lastCounts = {}

    while os.clock() - startTime < timeout do
        os.sleep(0.5)
        local current = getInterfaceContents(interfaceName)
        local allStable = true

        if outputSlots and #outputSlots > 0 then
            for _, slot in ipairs(outputSlots) do
                local beforeCount = (before[slot] and before[slot].count) or 0
                local currentCount = (current[slot] and current[slot].count) or 0
                if currentCount <= beforeCount then
                    allStable = false
                    break
                end
                if lastCounts[slot] and lastCounts[slot] ~= currentCount then
                    allStable = false
                end
                lastCounts[slot] = currentCount
            end
        else
            local hasChange = false
            for slot, item in pairs(current) do
                local beforeItem = before[slot]
                if not beforeItem or item.name ~= beforeItem.name or item.count ~= beforeItem.count then
                    hasChange = true
                    break
                end
            end
            if not hasChange then
                allStable = false
            end
        end

        if allStable then
            stableTicks = stableTicks + 1
        else
            stableTicks = 0
        end

        if stableTicks >= 2 then
            return true
        end
    end
    return false
end

local function btn_craft(selectedItem, batches)
    batches = batches or 1
    if not selectedItem or not data[selectedItem] then return false end

    local recipe = data[selectedItem]

    -- 1. ПОЛНАЯ ОЧИСТКА БОЧКИ перед началом
    clearBarrelToStorage()

    if recipe.type == "processing" and recipe.machine and recipe.machine ~= "crafting_table" then
        local before = getInterfaceContents(recipe.machine)
        if not pushIngredientsToProcessInterface(recipe, batches) then
            return false
        end

        local waitSlots = recipe.outputSlots or {}
        if not waitForProcessCompletion(recipe.machine, before, waitSlots, 15) then
            print("Process did not stabilize in time")
        end

        local ok, itemName, totalMoved = retrieveProcessOutputs(recipe, before)
        if not ok then
            print("Failed to collect process outputs")
            return false
        end

        print("Processed " .. tostring(totalMoved) .. " x " .. tostring(itemName))
        return true
    end

    -- 2. ЗАГРУЗКА ИНГРЕДИЕНТОВ
    local slots = {4, 5, 6, 13, 14, 15, 22, 23, 24}
    for i = 1, 9 do
        local neededItem = recipe.pattern[i]
        local targetSlot = slots[i]

        if neededItem and neededItem ~= " " then
            local needCount = batches
            local remaining = needCount

            for _, storage in ipairs(storages) do
                if remaining <= 0 then break end
                local items = getAllItemsFromStorage(storage.peripheral)
                for slot, item in pairs(items) do
                    if item.name == neededItem and item.count > 0 then
                        local take = math.min(remaining, item.count)
                        local moved = storage.peripheral.pushItems(barrel_name, slot, take, targetSlot)
                        remaining = remaining - moved
                        if remaining <= 0 then break end
                    end
                end
            end

            if remaining > 0 then
                print("Error: missing " .. neededItem)
                return false
            end
        end
    end

    -- 3. ПЕРЕМЕЩЕНИЕ В ЧЕРЕПАХУ
    local turtleSlot = 1
    for i = 1, 27 do
        if (i >= 4 and i < 7) or (i >= 13 and i < 16) or (i >= 22 and i < 25) then
            if turtleSlot <= 16 then
                if turtleSlot == 4 or turtleSlot == 8 then turtleSlot = turtleSlot + 1 end
                barrel.pushItems("turtle_0", i, 64, turtleSlot)
                turtleSlot = turtleSlot + 1
            end
        end
    end

    -- 4. КОМАНДА КРАФТА
    local modem = peripheral.wrap("bottom")
    if not modem then
        print("Error: Modem not found on bottom")
        return false
    end
    modem.open(1)
    local craftCount = batches * (recipe.craft or 1)
    modem.transmit(1, 1, { command = "craft", count = craftCount })

    -- 5. ЗАБИРАЕМ РЕЗУЛЬТАТ ИЗ ЧЕРЕПАХИ В БОЧКУ
    for i = 1, 16 do
        barrel.pullItems("turtle_0", i, 64)
    end

    return true
end




local function identifyMachine(name)
    local pType = peripheral.getType(name)
    
    if pType == "turtle" then
        return "crafting"
    -- Проверка на Modern Industrialization (обычно они имеют специфические типы)
    elseif pType and pType:find("modern_industrialization") then
        return "processing"
    -- Обычные печки или механизмы других модов
    elseif pType == "furnace" or pType == "blast_furnace" then
        return "processing"
    end
    return "unknown"
end




-- Получить общее количество предмета во всех хранилищах
local function getTotalItemCount(itemId)
    local total = 0
    for _, storage in ipairs(storages) do
        local items = getAllItemsFromStorage(storage.peripheral)
        for _, item in pairs(items) do
            if item.name == itemId then
                total = total + item.count
            end
        end
    end
    return total
end

local function buildCraftPlan(targetItem, desiredCount)
    local craftCount = {}
    local missing = {}
    
    -- Кэшируем содержимое складов
    local virtualInv = {}
    for _, storage in ipairs(storages) do
        local items = getAllItemsFromStorage(storage.peripheral)
        for _, item in pairs(items) do
            virtualInv[item.name] = (virtualInv[item.name] or 0) + item.count
        end
    end

    -- Внутренняя функция расчета
    local function calculate(item, amount, isFinal) -- Добавлен флаг isFinal
        -- Если это НЕ финальный предмет, сначала пытаемся взять из запасов
        if not isFinal then
            local available = virtualInv[item] or 0
            local takenFromInv = math.min(available, amount)
            
            virtualInv[item] = available - takenFromInv
            amount = amount - takenFromInv
        end

        -- Если всё еще нужно количество > 0 (или это принудительный крафт финала)
        if amount > 0 then
            local recipe = data[item]
            if recipe then
                local yield = recipe.craft or 1
                local batches = math.ceil(amount / yield)
                
                craftCount[item] = (craftCount[item] or 0) + batches
                
                for i = 1, 9 do
                    local ing = recipe.pattern[i]
                    if ing and ing ~= " " then
                        -- Ингредиенты — это уже не финал, для них используем инвентарь
                        calculate(ing, batches, false)
                    end
                end

                -- Учитываем излишки от крафта для будущих шагов этой цепочки
                local surplus = (batches * yield) - amount
                if surplus > 0 then
                    virtualInv[item] = (virtualInv[item] or 0) + surplus
                end
            else
                -- Рецепта нет и на складе пусто
                missing[item] = (missing[item] or 0) + amount
            end
        end
    end

    -- Запуск расчета: для целевого предмета ставим true, чтобы игнорировать его наличие на складе
    calculate(targetItem, desiredCount, true)

    if next(missing) then
        return nil, missing
    end
    return craftCount
end

-- Выполнить крафты по плану (без сброса бочки между крафтами)
local function executeCraftsPlan(plan, targetItem) -- Добавили targetItem
    if not plan or not next(plan) then
        print("All items are already in stock. No crafting needed!")
        return true
    end

    -- Логика определения глубины крафта (оставляем как было)
    local depth = {}
    local function getDepth(item)
        if depth[item] then return depth[item] end
        local recipe = data[item]
        if not recipe then depth[item] = 0 return 0 end
        local maxD = 0
        for i = 1, 9 do
            local ing = recipe.pattern[i]
            if ing and ing ~= " " then
                maxD = math.max(maxD, getDepth(ing) + 1)
            end
        end
        depth[item] = maxD
        return maxD
    end

    local sorted = {}
    for item in pairs(plan) do 
        getDepth(item)
        table.insert(sorted, item) 
    end
    table.sort(sorted, function(a, b) return depth[a] < depth[b] end)

    -- Выполнение крафта по шагам
    for _, item in ipairs(sorted) do
        local batches = plan[item]
        print("Step: " .. item .. " (" .. batches .. " batches)")
        
        local ok = btn_craft(item, batches)
        if not ok then return false end

        -- ПРОВЕРКА: Если это НЕ финальный предмет, убираем его в хранилище
        -- Если это финальный предмет (item == targetItem), оставляем в бочке
        if item ~= targetItem then
            print("Cleaning up intermediate: " .. item)
            clearBarrelToStorage()
        else
            print("Final item " .. item .. " stays in the barrel!")
        end
    end
    
    print("--- SUCCESS ---")
    return true
end

-- Основная функция крафта с отображением недостающих ресурсов
local function craftWithDependencies(selectedItem, multiplier)
    print("Building plan for: " .. selectedItem)
    local plan, missing = buildCraftPlan(selectedItem, multiplier)

    if not plan then
        print("Missing resources:")
        for item, count in pairs(missing) do
            print("- " .. item .. ": " .. count)
        end


        -- Вывод на монитор (коротко)
        win_count_craft.setBackgroundColour(colors.black)
        win_count_craft.clear()
        win_count_craft.setTextColour(colors.red)
        win_count_craft.setCursorPos(1,1)
        win_count_craft.write("Check console for missing items")
        sleep(2)
        return
    end

    print("Plan confirmed. Starting craft...")
    -- Передаем selectedItem вторым аргументом
    local ok = executeCraftsPlan(plan, selectedItem) 
    
    if ok then
        print("Crafting finished!")
    else
        print("Crafting failed during execution.")
    end
end









local function touch()
    while true do
        local event, side, x, y = os.pullEvent()

        if event == "monitor_touch" and side == "right" then
            print("The monitor on side " .. side .. " was touched at (" .. x .. ", " .. y .. ")")
            -- os.sleep(0.05) -- Небольшая задержка для предотвращения многократных срабатываний
            if x < btnX_add+8 and x >= btnX_add and y >= btnY_add and y < btnY_add+3 then
                -- Если уже выбран предмет для крафта, сначала отменяем его
                if selectedItem then
                    selectedItem = nil
                    displayRecipes()
                    win_count_craft.clear()
                end
                btn_add_active = true
                btn_add()
            end
            if x >= 2 and x < 7 and y == 21 then
                btn_add_active = false
                choise_window.setBackgroundColour(colors.black)
                choise_window.clear()
                if not btn_add_choise then
                    btn_addcraft()
                end
            end
            if x >= 8 and x < 13 and y == 21 then
                btn_add_active = false
                choise_window.setBackgroundColour(colors.black)
                choise_window.clear()
                if not btn_add_choise then
                    btn_addprocess()
                end
            end

            if x >= 28 and x < 30 and y == 20 then
                btn_yes()
            end
            if x >= 38 and x < 40 and y == 20 then
                btn_no()
            end
            if x >= 3 and x < 5 and y == 16 then 
                scroll_left()
            end
            if x >= 7 and x < 9 and y == 16 then 
                scroll_right()
            end

            -- Внутри функции touch(), в блоке выбора предмета:
            if x >= 3 and x < 44 and y >= 4 and y < 15 then
                if processSelectionActive then
                    local index = y - 3
                    local entry = processCandidates[index]
                    if entry then
                        selectedProcessInterface = entry.name
                        processSelectionActive = false
                        choise_window.setBackgroundColour(colors.black)
                        choise_window.clear()

                        win_count_craft.setBackgroundColour(colors.black)
                        win_count_craft.clear()
                        win_count_craft.setCursorPos(1,1)
                        win_count_craft.setTextColour(colors.white)
                        win_count_craft.write("Selected: " .. entry.name:sub(1, 24))

                        btn_addcraft()
                    end
                else
                    local index = y + scrollOffset - 3
                    if itemKeys[index] then

                        btn_add_active = false
                        choise_window.setBackgroundColour(colors.black)
                        choise_window.clear()
                        btn_add_choise = false


                        selectedItem = itemKeys[index] -- Сохраняем выбор
                        print("Selected item: " .. selectedItem)
                        
                        btn_craft_choose(selectedItem) -- Рисуем кнопки x1, x4...
                        displayRecipes()               -- ОБНОВЛЯЕМ СПИСОК (чтобы появилась подсветка)
                    end
                end
            end

            if x >= winX and x < winX + 30 and y >= winY and y < winY + 4 then
                local localX = x - winX + 1
                local localY = y - winY + 1
                local stepX = btnWidth + paddingX
                local column = math.floor((localX - 1) / stepX)
                local row = math.floor((localY - 1) / 2)
                local index = row * maxCols + column + 1
                
                if index >= 1 and index <= #multipliers then
                    local selectedMultiplier = multipliers[index]   -- множитель (количество крафтов)
                    
                    if selectedItem and data[selectedItem] then
                        local baseCount = data[selectedItem].craft
                        local totalToCraft = baseCount * selectedMultiplier   -- фактическое количество предметов
                        
                        print("--- ACTION ---")
                        print("Crafting: " .. selectedItem .. " x" .. totalToCraft)
                        
                        win_count_craft.setBackgroundColour(colors.black)
                        win_count_craft.clear()
                        win_count_craft.setCursorPos(1,1)
                        win_count_craft.setBackgroundColour(colors.gray)
                        win_count_craft.write("Crafting " .. selectedItem .. " x" .. totalToCraft)
                        
                        craftWithDependencies(selectedItem, totalToCraft)   -- передаём фактическое количество предметов
                        
                        selectedItem = nil
                        displayRecipes()
                        win_count_craft.setBackgroundColour(colors.black)
                        win_count_craft.clear()
                    else
                        print("Error: No item selected from list!")
                    end
                end
            end


        end


        if event == "monitor_touch" and side == "monitor_0" then
            if y == 3 then
                monitor_2.setBackgroundColour(colors.black)
                monitor_2.clear()
                clearBarrelToStorage()
                initMonitor_2()
            end
        end
    end
end


local function main()

    local allDevices = getAllDevices()
    print("Devices:", table.concat(allDevices, ", "))
    
    -- Инициализация
    initMonitor()
    createScrollWindow()
    loadRecipes()
    updateItemKeys()
    displayRecipes()
    initTurtle()
    initStorages()
    initMonitor_2()
    
    -- Отрисовка интерфейса
    drawAddButton()
    drawHorizontalLine()
    drawVerticalLine()
    drawTopHorizontalLine()
--    setupWindowHeader()
    touch()
end



main()
