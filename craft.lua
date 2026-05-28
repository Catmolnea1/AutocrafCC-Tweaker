local function initTurtle()
    turtle = peripheral.wrap("turtle_0")
    if not turtle then
        error("No turtle found on side 'turtle_0'", 0)
    end
end

local function craft()
    print(table.concat(peripheral.getNames(), ", "))
    local modem = peripheral.wrap("left") or error("No modem attached", 0)
    modem.open(1)

    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        print(("Message received on side %s on channel %d (reply to %d) from %f blocks away with message %s"):format(
            side, channel, replyChannel, distance, tostring(message)
        ))

        if tostring(message.command) == "craft" then
            if turtle then
                turtle.craft(message.count)
                print("Crafting completed: " .. message.count)
            else
                print("Error: turtle not initialized")
            end
        end
    end
end

-- Initialize turtle before starting craft loop
initTurtle()
craft()
