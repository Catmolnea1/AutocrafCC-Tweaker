local function initTurtle()
    local t = peripheral.wrap("turtle_0")
    if not t then
        error("No turtle found on side 'turtle_0'", 0)
    end
    return t
end

local function craft(turtle)
    print(table.concat(peripheral.getNames(), ", "))
    local modem = peripheral.wrap("left") or error("No modem attached", 0)
    modem.open(1)

    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        print(("Message received on side %s on channel %d (reply to %d) from %f blocks away with message %s"):format(
            side, channel, replyChannel, distance, tostring(message)
        ))

        if channel == 1 and message.command == "craft" then
            local requested = message.count
            local crafted = 0

            while crafted < requested do
                local remaining = requested - crafted
                local success = turtle.craft(remaining)

                if not success then
                    print("Warning: Craft operation failed at " .. crafted .. " items")
                    break
                end

                crafted = crafted + remaining
            end

            print("Crafting completed: " .. crafted .. " of " .. requested)
        end
    end
end

local turtle = initTurtle()
craft(turtle)
