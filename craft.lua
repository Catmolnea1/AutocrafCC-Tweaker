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
            turtle.craft(message.count)
            print(1)
        end
    end
end

craft()
