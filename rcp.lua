-- store tick rate as a variable for later use
tickRate = 10

--actually set the tick rate
setTickRate(tickRate)

-- variables for automatic logging stop/start
-- a counter for stopping the logging
shutdownCounter = 0
-- how long after shutdown should we keep logging? in seconds.
shutdownTime = 30
-- are we actually logging? keep track.
isLogging = false

-- variables for gear ratio calculations
-- set up the virtual channel
-- I know the supra only has ratios from -3.768 to 3.285
ratioId = addChannel("GearRatio", 10, 3, -5, 5)
-- reverse is a distinct ratio, so I can detect it
reverseRatio = 3.768
-- when using computed gear ratio for computation, how close
-- do we have to be before we call it close enough?
ratioTolerance = 0.15

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

function doGearRatio()
    -- the supra has a transmission output shaft speed sensor.
    -- I have this sensor wired to timer 1, so gear ratio calculation is easy
    local engineRpm = getTimerRpm(0)
    local driveshaftRpm = getTimerRpm(1)
    local ratio = 0

    if driveshaftRpm > 0 then
        -- avoid dividing by zero
        ratio = engineRpm/driveshaftRpm
    end

    if math.abs(ratio - reverseRatio) < ratioTolerance then
        -- make the ratio negative if we're in reverse.
        -- this is probably not something we strictly need, but it is amusing.
        ratio = -1 * ratio
    end

    -- set the actual virtual channel output
    setChannel(ratioId, ratio)
end

function onTick()
    doLogging()
    doGearRatio()
end
