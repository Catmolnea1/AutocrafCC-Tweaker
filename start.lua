local monitor = peripheral.wrap("right")
local monitor_2 = peripheral.wrap("monitor_0")
local scroll_window = nil
local win_count_craft = nil
local choise_window = nil
local choiseadd_window = nil

local path = "crafts.json"
local w, h = 0, 0
local data = {}
local itemKeys = {}
local scrollOffset = 0 -- Скролл списка рецептов

-- Состояния интерфейса
local currentTab = "recipe"       -- Активная вкладка: "recipe", "add", "edit", "machines"
local selectedMod = "ALL"         -- Выбранный мод для фильтрации
local uniqueMods = { "ALL" }      -- Список всех обнаруженных модов
local modOffset = 0               -- Прокрутка вкладок модов
local maxVisibleMods = 5          -- Сколько модов одновременно видно на экране
local isQuantityMode = false      -- Активен ли выбор количества предметов

local multipliers = {1, 4, 8, 16, 24, 32, 40, 48, 56, 64}
local maxCols = 5      
local btnWidth = 6     
local paddingX = 3 
local paddingY = 1     
local winX, winY = 3, 6 
local selectedItem = nil 
local currentRecipeType = "crafting"
local selectedProcessInterface = nil
local selectedProcessOutputSlots = {}
local processSelectionActive = false
local processCandidates = {}
local barrel = peripheral.wrap("minecraft:barrel_0")
local barrel_name = "minecraft:barrel_0"
local storages = {}
local bf = false
local patternc = {}
local item_name = ""
local craft_items = 0

-- ======================================================================
--  БАЗОВЫЕ ФУНКЦИИ И РАБОТА С УСТРОЙСТВАМИ
-- ======================================================================

local function getAllDevices()
    local allDevices = peripheral.getNames()
    return allDevices
end

local function isProcessInterface(name)
    local pType = peripheral.getType(name) or ""
    if name == barrel_name or pType == "turtle" then return false end
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
    if not device or not device.list then return {} end
    local items = {}
    local success, result = pcall(device.list)
    if success and result then
        for slot, item in pairs(result) do items[slot] = item end
    end
    return items
end

local function getInterfaceItemCount(name, itemName)
    local total = 0
    for _, item in pairs(getInterfaceContents(name)) do
        if item.name == itemName then total = total + item.count end
    end
    return total
end

local function getPatternFromInterface(name)
    local device = peripheral.wrap(name)
    if device and device.list then
        local inv = device.list()
        local pattern = {}
        for slot = 1, 9 do
            local item = inv[slot]
            pattern[slot] = item and item.name or " "
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
        pattern[i] = item and item.name or " "
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
    if not device then return false end
    local startTime = os.clock()
    local lastCount = getInterfaceItemCount(interfaceName, outputName)
    local stableTicks = 0
    while os.clock() - startTime < timeout do
        os.sleep(0.5)
        local currentCount = getInterfaceItemCount(interfaceName, outputName)
        local meetsExpected = not expectedCount or currentCount >= expectedCount
        if meetsExpected and currentCount == lastCount then
            stableTicks = stableTicks + 1
        else
            stableTicks = 0
        end
        lastCount = currentCount
        if stableTicks >= 2 and currentCount > 0 then return true end
    end
    return false
end

-- ======================================================================
--  ИНИЦИАЛИЗАЦИЯ И ХРАНИЛИЩА
-- ======================================================================

local function initMonitor()
    monitor.setBackgroundColour(colors.black)
    monitor.clear()
    monitor.setTextScale(1)
    w, h = monitor.getSize()
end

local function initTurtle()
    turtle = peripheral.wrap("turtle_0")
end

local function createScrollWindow()
    -- Основная рабочая область внутри рамок (Y: 6-24, Высота 19 строк)
    scroll_window = window.create(monitor, 3, 6, 78, 19)
    win_count_craft = window.create(monitor, 3, 6, 78, 19)
    choise_window = window.create(monitor, 3, 6, 78, 19)
    choiseadd_window = window.create(monitor, 3, 6, 78, 19)
end

local function initStorages()
    storages = {}
    local allDevices = getAllDevices()
    for _, name in ipairs(allDevices) do
        if string.sub(name, 1, 17) == "create:item_vault" then
            local storage = peripheral.wrap(name)
            table.insert(storages, {
                name = name,
                peripheral = storage,
                type = "create_vault"
            })
        end
    end
end

local function getAllItemsFromStorage(storagePeripheral)
    local items = {}
    if storagePeripheral.list then
        local success, result = pcall(storagePeripheral.list) 
        if success and result then return result end
    end
    local size = 1000 
    if storagePeripheral.size then
        local success, s = pcall(storagePeripheral.size)
        if success then size = s end
    end
    for slot = 1, size do
        local item = storagePeripheral.getItemDetail(slot)
        if item then items[slot] = item end
    end
    return items
end

local function findItemInStorages(itemId, count)
    count = count or 1
    for i = 1, 27 do
        local item = barrel.getItemDetail(i)
        if item and item.name == itemId and item.count >= count then
            return { name = barrel_name, peripheral = barrel, type = "barrel" }, i, item
        end
    end
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

local function clearBarrelToStorage()
    local totalMoved = 0
    if not barrel then return false end
    for i = 1, 27 do
        local item = barrel.getItemDetail(i)
        if item and item.count > 0 then
            local moved = false
            for _, storage in ipairs(storages) do
                local result = barrel.pushItems(storage.name, i, item.count)
                if result > 0 then
                    totalMoved = totalMoved + result
                    moved = true
                    break  
                end
            end
        end
    end
end

local function initMonitor_2()
    monitor_2.setBackgroundColour(colors.black)
    monitor_2.clear()
    local w2, h2 = monitor_2.getSize()
    monitor_2.setBackgroundColour(colors.gray)
    monitor_2.setCursorPos(1, math.floor(h2/2)+1)
    monitor_2.write("Push >>")
end

-- ======================================================================
--  ФИЛЬТРАЦИЯ МОДОВ И КОНФИГУРАЦИЯ
-- ======================================================================

local function loadRecipes()
    if fs.exists(path) then
        local file = fs.open(path, "r")
        local content = file.readAll()
        file.close()
        data = textutils.unserializeJSON(content) or {}
    else
        data = {}
    end
    return data
end

-- Динамическое обновление списка уникальных модов на основе рецептов
local function updateModList()
    local modsMap = {}
    for name, _ in pairs(data) do
        local mod = name:match("^([^:]+):") or "MINECRAFT"
        modsMap[mod:upper()] = true
    end
    
    uniqueMods = { "ALL" }
    local sorted = {}
    for m, _ in pairs(modsMap) do table.insert(sorted, m) end
    table.sort(sorted)
    for _, m in ipairs(sorted) do table.insert(uniqueMods, m) end
end

-- Фильтрация ключей по текущему моду
local function updateItemKeys()
    itemKeys = {}
    for name, _ in pairs(data) do
        local mod = (name:match("^([^:]+):") or "MINECRAFT"):upper()
        if selectedMod == "ALL" or mod == selectedMod then
            table.insert(itemKeys, name)
        end
    end
    table.sort(itemKeys)
end

-- ======================================================================
--  ОТРИСОВКА ИНТЕРФЕЙСА (БЕЗ БАГОВ)
-- ======================================================================

-- Полная перерисовка базового каркаса (Рамки, линии, вкладки)
local function drawStaticLayout()
    monitor.setBackgroundColour(colors.black)
    monitor.clear()

    -- Желтые рамки
    monitor.setBackgroundColour(colors.yellow)
    monitor.setCursorPos(1, 1)
    monitor.write(string.rep(" ", w))
    monitor.setCursorPos(1, 25)
    monitor.write(string.rep(" ", w))
    for i = 2, h do
        monitor.setCursorPos(1, i)
        monitor.write(" ")
        monitor.setCursorPos(82, i)
        monitor.write(" ")
    end

    -- 1. Отрисовка верхних Вкладок (Y: 2)
    local tabs = {
        { id = "recipe",   label = " RECIPE " },
        { id = "add",      label = "   ADD  " },
        { id = "edit",     label = "  EDIT  " },
        { id = "machines", label = "MACHINES" }
    }
    local startX = 3
    for _, t in ipairs(tabs) do
        monitor.setCursorPos(startX, 2)
        if currentTab == t.id then
            monitor.setBackgroundColour(colors.blue)
            monitor.setTextColour(colors.white)
        else
            monitor.setBackgroundColour(colors.gray)
            monitor.setTextColour(colors.white)
        end
        monitor.write(t.label)
        startX = startX + #t.label + 2
    end

    -- 2. Отрисовка Вкладок выбора модов (Y: 4)
    if currentTab == "recipe" and not isQuantityMode then
        monitor.setBackgroundColour(colors.black)
        monitor.setTextColour(colors.yellow)
        monitor.setCursorPos(3, 4)
        monitor.write("[<]") -- Стрелочка влево для модов

        local modX = 7
        for i = 1, maxVisibleMods do
            local idx = i + modOffset
            local modName = uniqueMods[idx]
            if modName then
                monitor.setCursorPos(modX, 4)
                if selectedMod == modName then
                    monitor.setBackgroundColour(colors.green)
                    monitor.setTextColour(colors.white)
                else
                    monitor.setBackgroundColour(colors.gray)
                    monitor.setTextColour(colors.white)
                end
                monitor.write(" " .. modName .. " ")
                modX = modX + #modName + 3
            end
        end
        monitor.setBackgroundColour(colors.black)
        monitor.setTextColour(colors.yellow)
        monitor.setCursorPos(77, 4)
        monitor.write("[>]") -- Стрелочка вправо для модов
    end

    -- 3. Стрелочки навигации снизу слева на желтой панели (Y: 25)
    monitor.setBackgroundColour(colors.yellow)
    monitor.setTextColour(colors.black)
    monitor.setCursorPos(3, 25)
    monitor.write("[<<]  [>>]")
end

-- Отрисовка списка контента вкладки Recipe
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
            else
                scroll_window.setBackgroundColour(colors.gray)
            end
            
            -- Имя предмета и количество за один крафт
            local recipe = data[itemId] or {}
            local craftCount = recipe.craft or 1
            local label = itemId:sub(1, 36)
            label = label .. string.rep(" ", 43 - #label)
            local countText = "x" .. tostring(craftCount)
            countText = countText .. string.rep(" ", 9 - #countText)
            scroll_window.setTextColour(colors.white)
            scroll_window.write(label)
            scroll_window.setTextColour(colors.yellow)
            scroll_window.write(countText)
            
            -- Кнопка Craft>> (Локальные X: 48-58)
            scroll_window.setCursorPos(48, i)
            scroll_window.setBackgroundColour(colors.lime)
            scroll_window.setTextColour(colors.black)
            scroll_window.write("[ Craft>> ]")
            
            -- Кнопка Delete (Локальные X: 61-72)
            scroll_window.setCursorPos(61, i)
            scroll_window.setBackgroundColour(colors.red)
            scroll_window.setTextColour(colors.white)
            scroll_window.write("[ Delete ]")
        end
    end
end

-- Главный менеджер экранов (переключает видимость окон)
local function redrawUI()
    drawStaticLayout()
    
    -- Скрываем все окна по умолчанию
    scroll_window.setVisible(false)
    win_count_craft.setVisible(false)
    choise_window.setVisible(false)
    choiseadd_window.setVisible(false)

    if currentTab == "recipe" then
        if isQuantityMode then
            win_count_craft.setVisible(true)
        else
            scroll_window.setVisible(true)
            displayRecipes()
        end
    elseif currentTab == "add" then
        choise_window.setVisible(true)
        -- Код отрисовки меню добавления
        choise_window.setBackgroundColour(colors.black)
        choise_window.clear()
        choise_window.setTextColour(colors.white)
        choise_window.setCursorPos(2, 2)
        choise_window.setBackgroundColour(colors.green)
        choise_window.write("[ Craft ]")
        choise_window.setCursorPos(15, 2)
        choise_window.write("[ Process ]")
    elseif currentTab == "machines" then
        scroll_window.setVisible(true)
        scroll_window.setBackgroundColour(colors.black)
        scroll_window.clear()
        scroll_window.setTextColour(colors.cyan)
        scroll_window.setCursorPos(2, 2)
        scroll_window.write("Connected Automation Interfaces List:")
        -- Тут в будущем будет список ваших машин
    else
        -- Вкладка EDIT
        scroll_window.setVisible(true)
        scroll_window.setBackgroundColour(colors.black)
        scroll_window.clear()
        scroll_window.setTextColour(colors.yellow)
        scroll_window.setCursorPos(2, 2)
        scroll_window.write("Edit Tab Window (Locked)")
    end
end

-- ======================================================================
--  УПРАВЛЕНИЕ ОКНОМ КОЛИЧЕСТВА КРАФТА
-- ======================================================================

local function drawQuantityButtons(itemName, baseCount)
    win_count_craft.setBackgroundColour(colors.black)
    win_count_craft.clear()
    
    win_count_craft.setCursorPos(2, 1)
    win_count_craft.setTextColour(colors.yellow)
    win_count_craft.write("Select amount for: " .. itemName:sub(1, 45))

    for i, m in ipairs(multipliers) do
        local totalToCraft = baseCount * m
        local column = (i - 1) % maxCols 
        local row = math.floor((i - 1) / maxCols) 

        local xPos = 2 + (column * (btnWidth + paddingX))
        local yPos = 3 + (row * (paddingY + 1))

        win_count_craft.setCursorPos(xPos, yPos)
        win_count_craft.setBackgroundColour(colors.blue)
        win_count_craft.setTextColour(colors.white)
        
        local label = "x" .. totalToCraft
        win_count_craft.write(label .. string.rep(" ", btnWidth - #label))
    end

    -- Кнопка отмены/возврата назад
    win_count_craft.setCursorPos(2, 15)
    win_count_craft.setBackgroundColour(colors.red)
    win_count_craft.setTextColour(colors.white)
    win_count_craft.write("[ CANCEL / BACK ]")
end

local function btn_craft_choose(itemName)
    local recipe = data[itemName]
    if recipe then
        isQuantityMode = true
        redrawUI()
        drawQuantityButtons(itemName, recipe.craft or 1)
    end
end

local function drawProcessSelection()
    processSelectionActive = true
    win_count_craft.setVisible(false)
    scroll_window.setVisible(true)
    scroll_window.setBackgroundColour(colors.black)
    scroll_window.clear()
    scroll_window.setTextColour(colors.white)
    
    scroll_window.setCursorPos(2, 1)
    scroll_window.write("Select process interface:")
    for i, entry in ipairs(processCandidates) do
        if i > 15 then break end
        scroll_window.setCursorPos(2, i + 1)
        scroll_window.write(i .. ". " .. entry.name .. " [" .. entry.type .. "]")
    end
end

-- ======================================================================
--  ЛОГИКА АВТОКРАФТА И АЛГОРИТМЫ
-- ======================================================================

function saveConfig(data)
    local file = fs.open(path, "w")
    local jsonString = "{"
    local first = true
    for itemId, recipe in pairs(data) do
        if not first then jsonString = jsonString .. "," end
        first = false
        jsonString = jsonString .. '\n  "' .. itemId .. '": {'
        jsonString = jsonString .. '\n    "type": "' .. recipe.type .. '",'
        jsonString = jsonString .. '\n    "craft": ' .. recipe.craft .. ','
        jsonString = jsonString .. '\n    "machine": "' .. recipe.machine .. '",'
        if recipe.outputSlots and #recipe.outputSlots > 0 then
            jsonString = jsonString .. '\n    "outputSlots": ['
            for i = 1, #recipe.outputSlots do
                jsonString = jsonString .. '\n      ' .. recipe.outputSlots[i]
                if i < #recipe.outputSlots then jsonString = jsonString .. "," end
            end
            jsonString = jsonString .. '\n    ],'
        end
        jsonString = jsonString .. '\n    "pattern": ['
        for i = 1, 9 do
            local patternItem = recipe.pattern[i] or " "
            jsonString = jsonString .. '\n      "' .. patternItem .. '"'
            if i < 9 then jsonString = jsonString .. "," end
        end
        jsonString = jsonString .. '\n    ]'
        jsonString = jsonString .. '\n  }'
    end
    jsonString = jsonString .. "\n}"
    file.write(jsonString)
    file.close()
end

function addCraft(resultName, count, pattern)
    if resultName == "" then return end
    data = loadRecipes() 
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
    saveConfig(data)
    updateModList()
    updateItemKeys()
end

local function btn_addcraft()
    -- 1. СНАЧАЛА считываем шаблон и запоминаем стартовое количество входящих ресурсов
    patternc = getBarrelPattern()

    local inputCounts = {}
    local inv = barrel.list()
    local slots = {4, 5, 6, 13, 14, 15, 22, 23, 24}
    
    -- Собираем стек каждого положенного предмета в сетке крафта
    for _, slot in ipairs(slots) do
        local item = inv[slot]
        if item and item.count > 0 then
            table.insert(inputCounts, item.count)
        end
    end

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
        -- Крафт через черепаху
        local modem = peripheral.wrap("bottom")
        local channel = 1
        local turtleSlot = 1 
        
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
        
        sleep(1.5) 

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

    -- ======================================================================
    --  ЛОГИКА АВТОМАТИЧЕСКОЙ НОРМАЛИЗАЦИИ КОЛИЧЕСТВА
    -- ======================================================================
    if craft_items > 0 and #inputCounts > 0 then
        -- Функция для поиска НОД двух чисел
        local function gcd(a, b)
            while b ~= 0 do
                a, b = b, a % b
            end
            return a
        end

        -- Собираем все числа в один массив: количества ингредиентов + результат крафта
        local allNumbers = {}
        for _, count in ipairs(inputCounts) do
            table.insert(allNumbers, count)
        end
        table.insert(allNumbers, craft_items)

        -- Ищем общий НОД для всей группы чисел
        local scaleFactor = allNumbers[1]
        for i = 2, #allNumbers do
            scaleFactor = gcd(scaleFactor, allNumbers[i])
        end

        -- Если общий делитель больше 1, значит крафт был пропорционально увеличен
        if scaleFactor > 1 then
            craft_items = math.floor(craft_items / scaleFactor)
            print("Recipe normalized! Scaled down by factor of: " .. scaleFactor)
        end
    end
    -- ======================================================================

    -- 2. ТОЛЬКО ТЕПЕРЬ рисуем окно подтверждения с результатом
    btn_add_choise = true
    choiseadd_window.setVisible(true) 
    choiseadd_window.setBackgroundColour(colors.black)
    choiseadd_window.clear()
    
    choiseadd_window.setTextColour(colors.white)
    choiseadd_window.setCursorPos(1,1)
    choiseadd_window.write("Would you like to save this craft?")
    choiseadd_window.setCursorPos(1,2)
    choiseadd_window.write("Found: " .. (item_name ~= "" and item_name or "None") .. " x" .. craft_items)

    choiseadd_window.setBackgroundColour(colors.lime)
    choiseadd_window.setTextColour(colors.black)
    choiseadd_window.setCursorPos(10,4)
    choiseadd_window.write(" YES ")
    
    choiseadd_window.setBackgroundColour(colors.red)
    choiseadd_window.setTextColour(colors.white)
    choiseadd_window.setCursorPos(20,4)
    choiseadd_window.write(" NO ")
end

local function btn_addprocess()
    currentRecipeType = "processing"
    selectedProcessInterface = nil
    selectedProcessOutputSlots = {}
    processCandidates = getProcessInterfaces()
    if #processCandidates == 0 then return end
    drawProcessSelection()
end

local function btn_craft(selectedItem, batches)
    batches = batches or 1
    if not selectedItem or not data[selectedItem] then return false end
    local recipe = data[selectedItem]
    clearBarrelToStorage()

    if recipe.type == "processing" and recipe.machine and recipe.machine ~= "crafting_table" then
        -- Код обработки механизмов...
        return true
    end

    local slots = {4, 5, 6, 13, 14, 15, 22, 23, 24}
    for i = 1, 9 do
        local neededItem = recipe.pattern[i]
        local targetSlot = slots[i]
        if neededItem and neededItem ~= " " then
            local remaining = batches
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
            if remaining > 0 then return false end
        end
    end

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

    local modem = peripheral.wrap("bottom")
    modem.open(1)
    local craftCount = batches * (recipe.craft or 1)
    modem.transmit(1, 1, { command = "craft", count = craftCount })
    for i = 1, 16 do barrel.pullItems("turtle_0", i, 64) end
    return true
end

local function buildCraftPlan(targetItem, desiredCount)
    local craftCount = {}
    local missing = {}
    local virtualInv = {}
    for _, storage in ipairs(storages) do
        local items = getAllItemsFromStorage(storage.peripheral)
        for _, item in pairs(items) do virtualInv[item.name] = (virtualInv[item.name] or 0) + item.count end
    end

    local function calculate(item, amount, isFinal)
        if not isFinal then
            local available = virtualInv[item] or 0
            local taken = math.min(available, amount)
            virtualInv[item] = available - taken
            amount = amount - taken
        end
        if amount > 0 then
            local recipe = data[item]
            if recipe then
                local yield = recipe.craft or 1
                local batches = math.ceil(amount / yield)
                craftCount[item] = (craftCount[item] or 0) + batches
                for i = 1, 9 do
                    local ing = recipe.pattern[i]
                    if ing and ing ~= " " then calculate(ing, batches, false) end
                end
                local surplus = (batches * yield) - amount
                if surplus > 0 then virtualInv[item] = (virtualInv[item] or 0) + surplus end
            else
                missing[item] = (missing[item] or 0) + amount
            end
        end
    end
    calculate(targetItem, desiredCount, true)
    if next(missing) then return nil, missing end
    return craftCount
end

local function executeCraftsPlan(plan, targetItem)
    if not plan or not next(plan) then return true end
    local depth = {}
    local function getDepth(item)
        if depth[item] then return depth[item] end
        local recipe = data[item]
        if not recipe then depth[item] = 0 return 0 end
        local maxD = 0
        for i = 1, 9 do
            local ing = recipe.pattern[i]
            if ing and ing ~= " " then maxD = math.max(maxD, getDepth(ing) + 1) end
        end
        depth[item] = maxD
        return maxD
    end
    local sorted = {}
    for item in pairs(plan) do getDepth(item) table.insert(sorted, item) end
    table.sort(sorted, function(a, b) return depth[a] < depth[b] end)

    for _, item in ipairs(sorted) do
        local batches = plan[item]
        local ok = btn_craft(item, batches)
        if not ok then return false end
        if item ~= targetItem then clearBarrelToStorage() end
    end
    return true
end

local function craftWithDependencies(selectedItem, multiplier)
    local plan, missing = buildCraftPlan(selectedItem, multiplier)
    if not plan then
        win_count_craft.setBackgroundColour(colors.black)
        win_count_craft.clear()
        win_count_craft.setTextColour(colors.red)
        win_count_craft.setCursorPos(2, 2)
        win_count_craft.write("Resources missing! Check computer console.")
        sleep(2)
        return
    end
    executeCraftsPlan(plan, selectedItem)
end

-- ======================================================================
--  ГЛАВНЫЙ ОБРАБОТЧИК НАЖАТИЙ ТЕРМИНАЛА (TOUCH)
-- ======================================================================

local function touch()
    while true do
        local event, side, x, y = os.pullEvent()

        if event == "monitor_touch" and side == "right" then
            
            -- [1] НАЖАТИЕ НА ВЕРХНИЕ ВКЛАДКИ (Y: 2)
            if y == 2 then
                if x >= 3 and x <= 12 then currentTab = "recipe" isQuantityMode = false
                elseif x >= 15 and x <= 21 then currentTab = "add" isQuantityMode = false
                elseif x >= 24 and x <= 31 then currentTab = "edit" isQuantityMode = false
                elseif x >= 34 and x <= 45 then currentTab = "machines" isQuantityMode = false
                end
                selectedItem = nil
                scrollOffset = 0
                redrawUI()
            
            -- [2] НАЖАТИЕ НА ВКЛАДКИ МОДОВ (Y: 4)
            elseif y == 4 and currentTab == "recipe" and not isQuantityMode then
                if x >= 3 and x <= 5 then
                    -- Стрелочка влево
                    modOffset = math.max(0, modOffset - 1)
                    redrawUI()
                elseif x >= 77 and x <= 79 then
                    -- Стрелочка вправо
                    modOffset = math.min(#uniqueMods - maxVisibleMods, modOffset + 1)
                    redrawUI()
                else
                    -- Клик по названию мода
                    local modX = 7
                    for i = 1, maxVisibleMods do
                        local idx = i + modOffset
                        local modName = uniqueMods[idx]
                        if modName then
                            local endX = modX + #modName + 1
                            if x >= modX and x <= endX then
                                selectedMod = modName
                                scrollOffset = 0
                                updateItemKeys()
                                redrawUI()
                                break
                            end
                            modX = endX + 2
                        end
                    end
                end
            
            -- [3] НАЖАТИЕ НА СТРЕЛОЧКИ СНИЗУ (Y: 25)
            elseif y == 25 then
                if x >= 3 and x <= 6 then
                    -- Скролл вверх/влево
                    scrollOffset = math.max(0, scrollOffset - 1)
                    if currentTab == "recipe" and not isQuantityMode then displayRecipes() end
                elseif x >= 9 and x <= 12 then
                    -- Скролл вниз/вправо
                    scrollOffset = math.min(#itemKeys - 19, scrollOffset + 1)
                    if currentTab == "recipe" and not isQuantityMode then displayRecipes() end
                end

            -- [4] ОБРАБОТКА ВНУТРЕННИХ КЛИКОВ ОКНА (Y: 6-24)
            elseif x >= 3 and x <= 80 and y >= 6 and y <= 24 then
                local localX = x - 3 + 1
                local localY = y - 6 + 1

                if currentTab == "recipe" then
                    if isQuantityMode then
                        -- Обработка клика по кнопкам множителей количества
                        if localX >= 2 and localX <= 75 and localY >= 3 and localY <= 12 then
                            local stepX = btnWidth + paddingX
                            local col = math.floor((localX - 2) / stepX)
                            local row = math.floor((localY - 3) / 2)
                            local idx = row * maxCols + col + 1
                            
                            if idx >= 1 and idx <= #multipliers and multipliers[idx] then
                                local selectedMultiplier = multipliers[idx]
                                if selectedItem and data[selectedItem] then
                                    local baseCount = data[selectedItem].craft or 1
                                    local totalToCraft = baseCount * selectedMultiplier
                                    
                                    craftWithDependencies(selectedItem, totalToCraft)
                                    isQuantityMode = false
                                    selectedItem = nil
                                    redrawUI()
                                end
                            end
                        elseif localY >= 15 and localY <= 16 and localX >= 2 and localX <= 20 then
                            -- Нажата кнопка возврата назад/Cancel
                            isQuantityMode = false
                            selectedItem = nil
                            redrawUI()
                        end
                    else
                        -- Обычный режим просмотра рецептов
                        local index = localY + scrollOffset
                        local itemId = itemKeys[index]
                        if itemId then
                            if localX >= 1 and localX <= 45 then
                                selectedItem = itemId
                                displayRecipes()
                            elseif localX >= 48 and localX <= 58 then
                                -- Кнопка [ Craft>> ]
                                selectedItem = itemId
                                btn_craft_choose(itemId)
                            elseif localX >= 61 and localX <= 72 then
                                -- Кнопка [ Delete ]
                                data[itemId] = nil
                                saveConfig(data)
                                updateModList()
                                updateItemKeys()
                                displayRecipes()
                            end
                        end
                    end
                
                elseif currentTab == "add" then
                    -- Логика добавления рецептов
                    if processSelectionActive then
                        if localY >= 2 and localY <= #processCandidates + 1 then
                            local entry = processCandidates[localY - 1]
                            if entry then
                                selectedProcessInterface = entry.name
                                processSelectionActive = false
                                btn_addcraft()
                            end
                        end
                    elseif btn_add_choise then
                        -- Проверяем 3-ю строку, где нарисованы YES и NO
                        if localY == 4 then
                            -- Клик по YES (координата X: 10)
                            if localX >= 10 and localX <= 14 then
                                if item_name and item_name ~= "" then
                                    addCraft(item_name, craft_items, patternc)
                                else
                                    print("Error: item_name is empty")
                                end
                                btn_add_choise = false
                                currentTab = "recipe"
                                redrawUI()
                            -- Клик по NO (координата X: 20)
                            elseif localX >= 20 and localX <= 24 then
                                btn_add_choise = false
                                currentTab = "recipe"
                                redrawUI()
                            end
                        end
                    else
                        if localY == 2 then
                            if localX >= 2 and localX <= 11 then
                                currentRecipeType = "crafting"
                                btn_addcraft()
                            elseif localX >= 15 and localX <= 26 then
                                btn_addprocess()
                            end
                        end
                    end
                end
            end
        end

        -- Вспомогательный монитор для очистки бочки
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

-- ======================================================================
--  ОСНОВНОЙ СТАРТ
-- ======================================================================

local function main()
    initMonitor()
    createScrollWindow()
    loadRecipes()
    
    updateModList()
    updateItemKeys()
    
    initTurtle()
    initStorages()
    initMonitor_2()
    
    redrawUI()
    touch()
end

main()