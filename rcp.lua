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

-- keep track of all the analog channel numbers
fuelLevelChannel = 0
oilTempChannel = 1
coolantPressureChannel = 2
coolantTempChannel = 3
oilPressureChannel = 4
engineTempChannel = 5
batteryVoltageChannel = 7

-- keep track of the gpio channel meaning
fanEnableGpio = 0
warnGpio = 1

-- variables for gear ratio calculations
-- set up the virtual channel for gear ratio
-- I know the supra only has ratios from -3.768 to 3.285
ratioId = addChannel("GearRatio", 10, 3, -5, 5)
-- set up the virtual channel for gear number
-- note that you'd have to change the range if you have more gears
gearId = addChannel("Gear", 10, 0, -1, 5)
-- reverse is a distinct ratio, so I can detect it
reverseRatio = 3.768
-- gear ratios for all the other gears
firstRatio = 3.285
secondRatio = 1.894
thirdRatio = 1.275
fourthRatio = 1.00
fifthRatio = 0.783
-- when using computed gear ratio for computation, how close
-- do we have to be before we call it close enough?
ratioTolerance = 0.15

-- what temperature are we going to turn the fan on and off?
-- I'm making them different so the fan doesn't turn on and off a bunch
-- of times when we're near the fanOnTemp
fanOnSlowTemp = 170
fanOffSlowTemp = 168
-- turn on the fan at a higher temperature when going fast
fanOnFastTemp = 225
fanOffFastTemp = 220
-- what is the speed we're calling fast?
fanFastThreshold = 10
-- it seems like getGpio isn't doing what I want for the fan, so keep track
-- of fan status on my own so I can make sure to keep the fan from bouncing
-- on and off all the time.
fanEnabled = false

-- warning function stuff. I chose these values by searching for mechanical
-- warning light switches and looking at their setpoints.
warningCoolantTemperature = 215
warningOilTemperature = 255
warningOilPressure = 3 -- should really be a function of RPM
warningLowCoolantPressure = -16 -- we've been having problems with this sensor, so basically turn off the low warning
warningHighCoolantPressure = 15
coolantPressureMinValidTemp = 100 -- coolant pressure doesn't develop until things get warm

function doWarn()
    -- I'm assuming rpm is channel 0 here
    local rpm = getTimerRpm(0)
    local coolantTemp = getAnalog(coolantTempChannel)
    local engineTemp = getAnalog(engineTempChannel)
    local oilTemp = getAnalog(oilTempChannel)
    local oilPressure = getAnalog(oilPressureChannel)
    local coolantPressure = getAnalog(coolantPressureChannel)
    if rpm > 200 then
        -- if the engine is spinning even a bit, start caring about warnings..
        if oilPressure < warningOilPressure then
            println('oil pressure low!')
            setGpio(warnGpio, 1)
        elseif coolantTemp >= warningCoolantTemperature then
            println('coolant temp high!')
            setGpio(warnGpio, 1)
        elseif engineTemp >= warningCoolantTemperature then
            println('engine temp high!')
            setGpio(warnGpio, 1)
        elseif oilTemp >= warningOilTemperature then
            println('oil temp high!')
            setGpio(warnGpio, 1)
        elseif (coolantTemp > coolantPressureMinValidTemp) and coolantPressure <= warningLowCoolantPressure then
            println('coolant pressure low!')
            setGpio(warnGpio, 1)
        elseif (coolantTemp > coolantPressureMinValidTemp) and coolantPressure >= warningHighCoolantPressure then
            println('coolant pressure high!')
            setGpio(warnGpio, 1)
        else
            -- if there's nothing else going wrong, turn off the warning!
            setGpio(warnGpio, 0)
        end
    else
        -- if the engine is not running, turn off the warning.
        -- TODO: initial test and sticky warning after shutdown?
        setGpio(warnGpio, 0)
    end
end

function doFan()
    local coolantTemp = getAnalog(coolantTempChannel)
    local engineTemp = getAnalog(engineTempChannel)
    local speed = getGpsSpeed()
    if speed < fanFastThreshold then
        if coolantTemp >= fanOnSlowTemp or engineTemp >= fanOnSlowTemp then
            -- enable the fan
            if not fanEnabled then
                println('fan on!')
            end
            setGpio(fanEnableGpio, 1)
            fanEnabled = true
        elseif fanEnabled and (coolantTemp >= fanOffSlowTemp or engineTemp >= fanOffSlowTemp) then
            setGpio(fanEnableGpio, 1)
            println('keeping fan on a little longer...')
        else
            if fanEnabled then
                println('fan off!')
            end
            setGpio(fanEnableGpio, 0)
            fanEnabled = false
        end
    else
        if coolantTemp >= fanOnFastTemp or engineTemp >= fanOnFastTemp then
            -- enable the fan
            if not fanEnabled then
                println('fan on!')
            end
            setGpio(fanEnableGpio, 1)
            fanEnabled = true
        elseif fanEnabled and (coolantTemp >= fanOffFastTemp or engineTemp >= fanOffFastTemp) then
            setGpio(fanEnableGpio, 1)
            println('keeping fan on a little longer...')
        else
            if fanEnabled then
                println('fan off!')
            end
            setGpio(fanEnableGpio, 0)
            fanEnabled = false
        end
    end
end

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

    local gearNum = 0

    -- now use this computed ratio to figure out what gear we're in.
    if math.abs(ratio - reverseRatio) < ratioTolerance then
        -- make the ratio negative if we're in reverse.
        -- this is probably not something we strictly need, but it is amusing.
        ratio = -1 * ratio
        gearNum = -1
    elseif math.abs(ratio - firstRatio) < ratioTolerance then
        gearNum = 1
    elseif math.abs(ratio - secondRatio) < ratioTolerance then
        gearNum = 2
    elseif math.abs(ratio - thirdRatio) < ratioTolerance then
        gearNum = 3
    elseif math.abs(ratio - fourthRatio) < ratioTolerance then
        gearNum = 4
    elseif math.abs(ratio - fifthRatio) < ratioTolerance then
        gearNum = 5
    else
        -- we must be coasting or stopped...
        gearNum = 0
    end

    -- set the actual virtual channel outputs
    setChannel(ratioId, ratio)
    setChannel(gearId, gearNum)
end

function onTick()
    doWarn()
    doFan()
    doLogging()
    doGearRatio()
end
