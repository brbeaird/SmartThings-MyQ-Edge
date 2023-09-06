local caps = require('st.capabilities')
local utils = require('st.utils')
local neturl = require('net.url')
local log = require('log')
local json = require('dkjson')
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
http.TIMEOUT = 5
local ltn12 = require('ltn12')
local httpUtil = require('httpUtil')
local socket = require('socket')
local config = require('config')

--Custom capabilities
local myqStatusCap = caps['towertalent27877.myqstatus']
local myqServerAddressCap = caps['towertalent27877.myqserveraddress']
local healthCap = caps['towertalent27877.health']

--Device type info
local myqDoorFamilyName = 'garagedoor'
local myqLampFamilyName = 'lamp'
local doorDeviceProfile = 'MyQDoor.v1'
local lampDeviceProfile = 'MyQLamp.v1'
local lockDeviceProfile = 'MyQLock.v1'
local updateAvailable = false

--Prevent spamming bad auth info
local authIsBad = false

--Allow for occasional MyQ errors
local consecutiveFailureCount = 0
local consecutiveFailureThreshold = 10

--Handle skipping a refresh iteration if a command was just issued
local commandIsPending = false

--Main exported object
local command_handler = {}

--Allow resetting auth flag from outside
function command_handler.resetAuth()
  authIsBad = false
end

------------------
-- Refresh command
function command_handler.refresh(driver, callingDevice, skipScan, firstAuth)

  if commandIsPending == true then
    log.info('Skipping refresh to let command settle.')
    commandIsPending = false
    return
  end

  if authIsBad == true then
    log.info('Bad auth.')
    return
  end

  local myQController

  --If called from controller, shortcut it
  if (callingDevice.device_network_id == 'MyQController') then
    myQController = callingDevice

  --Otherwise, look up the controller device
  else
    local device_list = driver:get_devices() --Grab existing devices
    local deviceExists = false
    for _, device in ipairs(device_list) do
      if device.device_network_id == 'MyQController' then
        myQController = driver.get_device_info(driver, device.id, true)
      end
    end
  end

  --Handle manual IP entry
  if myQController.preferences.serverIp ~= '' then
    skipScan = 1
  end

  --Update controller server address
  local currentControllerServerAddress = myQController:get_latest_state('main', "towertalent27877.myqserveraddress", "serverAddress", "unknown")
  local serverAddress = "Pending"
  if myQController.model ~= '' then
    serverAddress = myQController.model
  end
  if currentControllerServerAddress ~= serverAddress then
    myQController:emit_event(myqServerAddressCap.serverAddress(serverAddress))
  end

--Handle blank auth info
  if myQController.preferences.email == '' or myQController.preferences.password == '' then
    log.info('No credentials yet. Waiting.')
    local defaultAuthStatus = 'Awaiting credentials'
    local currentStatus = myQController:get_latest_state('main', "towertalent27877.myqstatus", "statusText", "unknown")
    if currentStatus ~= defaultAuthStatus then
      log.info('No credentials yet. Waiting.' ..currentStatus)
      myQController:emit_event(myqStatusCap.statusText(defaultAuthStatus))
    end
    consecutiveFailureCount = 100 --Force immediate display of errors once auth is entered
    return
  end

  --Handle missing myq server URL - try and broadcast to auto-discover
  if myQController.model == '' then
    doBroadcast(driver, callingDevice, myQController)
    return
  end


  --Call out to MyQ server
  local loginInfo = {email=myQController.preferences.email, password=myQController.preferences.password}
  local data = {auth=loginInfo}
  local success, code, res_body = httpUtil.send_lan_command(myQController.model, 'POST', 'devices', data)

  --Handle server result
  if success and code == 200 then
    local raw_data = json.decode(table.concat(res_body)..'}') --ltn12 bug drops last  bracket
    consecutiveFailureCount = 0
    local installedDeviceCount = 0

    --New versions have a top-level object
    local myqDevices
    if raw_data.meta then
      myqDevices = raw_data.devices
      if raw_data.meta.updateAvailable == true then
        updateAvailable = true
      else
        updateAvailable = false
      end
    else
      myqDevices = raw_data
    end

    --Loop over latest data from MyQ
    local myqDeviceCount = 0
    for devNumber, myqDevice in pairs(myqDevices) do

      --Doors and lamp modules
      if myqDevice.device_family == myqDoorFamilyName or myqDevice.device_family == myqLampFamilyName then
        myqDeviceCount = myqDeviceCount + 1
        local deviceExists = false
        local stDevice

        --Determine if device exists in SmartThings
        local device_list = driver:get_devices() --Grab existing devices
        for _, device in ipairs(device_list) do
          if device.device_network_id == myqDevice.serial_number then
            deviceExists = true
            stDevice = device
          end
        end

        --If this device already exists in SmartThings, update the status
        if deviceExists then
          installedDeviceCount = installedDeviceCount + 1

          --Set health online
          stDevice:online()
          local currentHealthStatus = stDevice:get_latest_state('main', "towertalent27877.health", "healthStatus", "unknown")
          if currentHealthStatus ~= 'Online' then
            stDevice:emit_event(healthCap.healthStatus('Online'))
          end

          local defaultStatus = 'Connected'
          local currentStatus = stDevice:get_latest_state('main', "towertalent27877.myqstatus", "statusText", "unknown")
          if currentStatus ~= defaultStatus then
            stDevice:emit_event(myqStatusCap.statusText(defaultStatus))
          end

          --Keep URL in sync (model and serverAddress cap)
          if stDevice.model ~= myQController.model then
            log.trace('Device ' ..stDevice.label .. ': updating URL to ' ..myQController.model)
            assert (stDevice:try_update_metadata({model = myQController.model}), 'failed to update device.')
          end
          local currentServerAddress = stDevice:get_latest_state('main', "towertalent27877.myqserveraddress", "serverAddress", "unknown")
          if currentServerAddress ~= myQController.model then
            stDevice:emit_event(myqServerAddressCap.serverAddress(myQController.model))
          end

          --Door-specifics
          if myqDevice.device_family == myqDoorFamilyName and myqDevice then
            local doorState = myqDevice.state.door_state

            --Doors
            if (stDevice.vendor_provided_label == doorDeviceProfile) then
              local stState = stDevice:get_latest_state('main', caps.doorControl.ID, "door", "unknown")
              if stState ~= doorState then
                stDevice:emit_event(caps.doorControl.door(doorState))

              --Switch/Contact capabilities
              local currentSwitchState = stDevice:get_latest_state('main', caps.switch.switch.ID, "switch", "unknown")
              local currentContactState = stDevice:get_latest_state('main', caps.contactSensor.contact.ID, "contact", "unknown")

                if doorState == 'closed' then
                  if currentSwitchState ~= 'off' then
                    stDevice:emit_event(caps.switch.switch.off())
                  end
                  if currentContactState ~= 'closed' then
                    stDevice:emit_event(caps.contactSensor.contact.closed())
                  end

                else
                  if currentSwitchState ~= 'on' then
                    stDevice:emit_event(caps.switch.switch.on())
                  end
                  if currentContactState ~= 'open' then
                    stDevice:emit_event(caps.contactSensor.contact.open())
                  end
                end
              end
            end

            --Locks
            if (stDevice.vendor_provided_label == lockDeviceProfile) then
              local lockStatus
              if doorState == 'closed' or doorStatus == 'closing' then
                lockStatus = 'locked'
              else
                lockStatus = 'unlocked'
              end
              local stState = stDevice:get_latest_state('main', caps.lock.ID, "lock", "unknown")
              if stState ~= lockStatus then
                log.trace('Lock ' ..stDevice.label .. ': setting status to ' ..lockStatus)
                stDevice:emit_event(caps.lock.lock(lockStatus))
              end
            end
          end

          --Lamp-specifics
          if myqDevice.device_family == myqLampFamilyName then

            local lampState = myqDevice.state.lamp_state
            local stState = stDevice:get_latest_state('main', caps.switch.switch.ID, "switch", "unknown")

            if stState ~= lampState then
              log.trace('Lamp ' ..stDevice.label .. ': setting status to ' ..lampState)
              stDevice:emit_event(caps.switch.switch(lampState))
            end
          end

        --Create new devices
        else

          --Respect include list setting (if applicable)
          local deviceIncluded = false
          if myQController.preferences.includeList == '' then
            deviceIncluded = true
          else
            deviceIncluded = false
            for i in string.gmatch(myQController.preferences.includeList, "([^,]+)") do
              if i == myqDevice.name then
                deviceIncluded = true
              end
           end
          end

          if deviceIncluded == true then

            local profileName

            --Door/lock
            if myqDevice.device_family == myqDoorFamilyName then
              if myQController.preferences.useLocks ~= true then
                profileName = doorDeviceProfile
              else
                profileName = lockDeviceProfile
              end
            end

            --Lamp
            if myqDevice.device_family == 'lamp' then
              profileName = lampDeviceProfile
            end

            log.info('Ready to create ' ..myqDevice.name ..' ('..myqDevice.serial_number ..') ' ..profileName)

            local metadata = {
              type = 'LAN',
              device_network_id = myqDevice.serial_number,
              label = myqDevice.name,
              profile = profileName,
              manufacturer = myqDevice.device_platform,
              model = myQController.model,
              vendor_provided_label = profileName,
              parent_device_id = myQController.id
            }
            assert (driver:try_create_device(metadata), "failed to create device")
            installedDeviceCount = installedDeviceCount + 1
          else
            --log.info(myqDevice.name ..' not found in device inclusion list.')
          end
        end
      end
    end

    --Update controller status
    log.info('Refresh successful via ' ..myQController.model ..'. MyQ devices: ' ..myqDeviceCount ..', ST-installed devices: ' ..installedDeviceCount)
    myQController:online()
    local newStatus = 'Connected: ' ..installedDeviceCount ..' devices'
    if updateAvailable == true then
      newStatus = newStatus ..' (Bridge server update available)'
    end
    local currentStatus = myQController:get_latest_state('main', "towertalent27877.myqstatus", "statusText", "unknown")
    if currentStatus ~= newStatus then
      myQController:emit_event(myqStatusCap.statusText(newStatus))
    end

  elseif code == 401 and firstAuth == 1 then
    --Update all devices to show invalid auth
    local device_list = driver:get_devices() --Grab existing devices
        for _, device in ipairs(device_list) do
          device:emit_event(myqStatusCap.statusText('Invalid credentials.'))
        end
    authIsBad = true
    return

  else

    --The MyQ API is unreliable. Allow up to 10 failures in a row before we display failure
    consecutiveFailureCount = consecutiveFailureCount + 1
    if consecutiveFailureCount > consecutiveFailureThreshold then

      --Update all devices to show server offline
      local offlineStatus = 'Error: MyQ Bridge Offline: ' ..myQController.model
      local device_list = driver:get_devices() --Grab existing devices
      for _, device in ipairs(device_list) do
        device:offline()

        --Set health status cap (needed for routines)
        local currentHealthStatus = device:get_latest_state('main', "towertalent27877.health", "healthStatus", "unknown")
        if currentHealthStatus ~= 'Offline' then
          device:emit_event(healthCap.healthStatus('Offline'))
        end

        --Sets status text
        local currentStatus = device:get_latest_state('main', "towertalent27877.myqstatus", "statusText", "unknown")
        if currentStatus ~= offlineStatus then
          log.info('Setting offline' ..currentStatus)
          device:emit_event(myqStatusCap.statusText(offlineStatus))
        end
      end
    end

    --If refresh failed with no response at all, try a UDP search to try and auto detect the server (maybe the IP or port changed)
    log.error('Refresh Failed.')

    if (skipScan ~= 1) then
      doBroadcast(driver, device, myQController)
    end
  end
end

function doBroadcast(driver, device, myQController)

  if driver.server.ip == nil then
    log.info('Refresh: waiting for driver http startup')
    return
  end

  log.info('Send broadcast looking for bridge server')
  local upnp = socket.udp()
  upnp:setsockname('*', 0)
  upnp:setoption('broadcast', true)
  upnp:settimeout(config.MC_TIMEOUT)

  -- Broadcast search
  log.info('Listening for a response at ' ..driver.server.ip ..':' ..driver.server.port ..':' ..myQController.id)
  local mSearchText = config.MSEARCH:gsub('IP_PLACEHOLDER', driver.server.ip)
  mSearchText = mSearchText:gsub('PORT_PLACEHOLDER', driver.server.port)
  mSearchText = mSearchText:gsub('ID_PLACEHOLDER', myQController.id)
  upnp:sendto(mSearchText, config.MC_ADDRESS, config.MC_PORT)
  local res = upnp:receive()
  upnp:close()
end

----------------
-- Device commands

--Door--
function command_handler.doorControl(driver, device, commandParam)
  commandIsPending = true
  local command = commandParam.command
  log.trace('Sending door command: ' ..command)
  local success = httpUtil.send_lan_command(device.model ..'/' ..device.device_network_id, 'POST', 'control', {command=command, auth=getLoginDetails(driver)})

  local pendingStatus
  if command == 'open' then
    pendingStatus = 'opening'
  else
    pendingStatus = 'closing'
  end

  if success then
    return device:emit_event(caps.doorControl.door(pendingStatus))
  end
  log.error('no response from device')
  return device:emit_event(myqStatusCap.statusText(command ..' command failed'))
end


--Switch--
function command_handler.switchControl(driver, device, commandParam)
  local command = commandParam.command
  log.trace('Sending switch command: ' ..command)

  --If this is a door, jump over to open/close
  if (device.vendor_provided_label == doorDeviceProfile) then
    if command == 'on' then
      return command_handler.doorControl(driver, device, {command='open'})
    else
      return command_handler.doorControl(driver, device, {command='close'})
    end
  end

  --Send it
  local success = httpUtil.send_lan_command(device.model ..'/' ..device.device_network_id, 'POST', 'control', {command=command, auth=getLoginDetails(driver)})

  --Handle result
  if success then
    if command == 'on' then
      return device:emit_event(caps.switch.switch.on())
    else
      return device:emit_event(caps.switch.switch.off())
    end
  end

  --Handle bad result
  log.error('no response from device')
  device:emit_event(myqStatusCap.statusText(command ..' command failed'))
  return false
end

--Lock--
function command_handler.lockControl(driver, device, commandParam)
  commandIsPending = true
  local command = commandParam.command
  log.trace('Sending lock command: ' ..command)

  --Translate to door commands
  local doorCommand
  if (command == 'unlock') then
    doorCommand = 'open'
  else
    doorCommand = 'close'
  end

  --Send it
  local success = httpUtil.send_lan_command(device.model ..'/' ..device.device_network_id, 'POST', 'control', {command=doorCommand, auth=getLoginDetails(driver)})

  --Handle result
  if success then
    commandIsPending = true
    device:emit_event(myqStatusCap.statusText(command ..' in progress..'))
    if command == 'unlock' then
      return device:emit_event(caps.lock.lock('unlocked'))
    else
      return device:emit_event(caps.lock.lock('locked'))
    end
  end

  --Handle bad result
  commandIsPending = false
  log.error('no response from device')
  device:emit_event(myqStatusCap.statusText(command ..' command failed'))
  return device:emit_event(caps.lock.lock("unknown"))
end

function command_handler.getControllerDevice(driver)
  local device_list = driver:get_devices() --Grab existing devices
  for _, device in ipairs(device_list) do
    if device.device_network_id == 'MyQController' then
      return driver.get_device_info(driver, device.id)
    end
  end
end

function getLoginDetails(driver)

  --Email/password are stored on the controller device. Find it.
  local myQController
  local device_list = driver:get_devices() --Grab existing devices
  local deviceExists = false
  for _, device in ipairs(device_list) do
    if device.device_network_id == 'MyQController' then
      myQController = driver.get_device_info(driver, device.id)
    end
  end
  return {email=myQController.preferences.email, password=myQController.preferences.password}
end

return command_handler