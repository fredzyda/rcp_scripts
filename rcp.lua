-- store tick rate as a variable for later use
tickRate = 10

--actually set the tick rate
setTickRate(tickRate)

-- a counter for stopping the logging
shutdownCounter = 0
-- how long after shutdown should we keep logging? in seconds.
shutdownTime = 30
-- are we actually logging? keep track.
isLogging = false

function doLogging()
    local gps = getGpsQuality()
    -- I'm assuming rpm is channel 0 here
    local rpm = getTimerRpm(0)
    if gps > 0 and rpm > 0 and not isLogging then
        -- start logging if we have a gps fix and the engine is turning
        println('logging')
        startLogging()
        shutdownCounter = 0
        isLogging = true
    elseif isLogging and rpm <= 0 then
        -- if the engine stopped, start counting ticks then stop logging.
        -- this keeps the log from constantly stopping if you stall a lot.
        shutdownCounter = shutdownCounter + 1
        println('shutdown counter: ' ..shutdownCounter)
        if shutdownCounter > (shutdownTime * tickRate) then
            stopLogging()
            println('stopping logging')
            isLogging = false
        end
    end
end

function onTick()
    doLogging()
end
