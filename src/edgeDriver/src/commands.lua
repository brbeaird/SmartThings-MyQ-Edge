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

local myqDoorFamilyName = 'garagedoor'
local myqLampFamilyName = 'lamp'
local doorDeviceProfile = 'MyQDoor.v1'
local lampDeviceProfile = 'MyQLamp.v1'
local authIsBad = false
local consecutiveFailureCount = 0
local consecutiveFailureThreshold = 20

local command_handler = {}

local myqStatusCap = caps[ 'towertalent27877.myqstatus' ]

function command_handler.resetAuth()
  authIsBad = false
end

------------------
-- Refresh command
function command_handler.refresh(driver, callingDevice, skipScan, firstAuth)

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

--Handle blank auth info
  if myQController.preferences.email == '' or myQController.preferences.password == '' then
    local defaultAuthStatus = 'Awaiting credentials'
    local currentStatus = myQController:get_latest_state('main', "towertalent27877.myqstatus", "statusText", "unknown")
    if currentStatus ~= defaultAuthStatus then
      log.info('No credentials yet. Waiting.' ..currentStatus)
      myQController:emit_event(myqStatusCap.statusText(defaultAuthStatus))
    end
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

    --Loop over latest data from MyQ
    local myqDeviceCount = 0
    for devNumber, devObj in pairs(raw_data) do

      --Doors and lamp modules
      if devObj.device_family == myqDoorFamilyName or devObj.device_family == myqLampFamilyName then
        myqDeviceCount = myqDeviceCount + 1
        local deviceExists = false
        local stDevice

        --Determine if device exists in SmartThings
        local device_list = driver:get_devices() --Grab existing devices
        for _, device in ipairs(device_list) do
          if device.device_network_id == devObj.serial_number then
            deviceExists = true
            stDevice = device
          end
        end

        --If this device already exists in SmartThings, update the status
        if deviceExists then
          installedDeviceCount = installedDeviceCount + 1
          stDevice:online()
          local defaultStatus = 'Connected'
          local currentStatus = stDevice:get_latest_state('main', "towertalent27877.myqstatus", "statusText", "unknown")
          if currentStatus ~= defaultStatus then
            stDevice:emit_event(myqStatusCap.statusText(defaultStatus))
          end

          --Keep URL in sync
          if stDevice.model ~= myQController.model then
            log.trace('Device ' ..stDevice.label .. ': updating URL to ' ..myQController.model)
            assert (stDevice:try_update_metadata({model = myQController.model}), 'failed to update device.')
          end

          --Door-specifics
          if devObj.device_family == myqDoorFamilyName then

            local doorState = devObj.state.door_state
            local stState = stDevice:get_latest_state('main', caps.doorControl.ID, "door", 0)

            if stState ~= doorState then
              log.trace('Door ' ..stDevice.label .. ': setting status to ' ..doorState)
              stDevice:emit_event(caps.doorControl.door(doorState))

              if doorState == 'closed' then
                stDevice:emit_event(caps.switch.switch.off())
              else
                stDevice:emit_event(caps.switch.switch.on())
              end
            end
          end

          --Lamp-specifics
          if devObj.device_family == myqLampFamilyName then

            local lampState = devObj.state.lamp_state
            local stState = stDevice:get_latest_state('main', caps.switch.switch.ID, "switch", 0)

            if stState ~= lampState then
              log.trace('Lamp ' ..stDevice.label .. ': setting status to ' ..lampState)
              stDevice:emit_event(caps.switch.switch(lampState))
            end
          end

        --Create new devices
        else

          --Respect include list setting (if applicable)
          if myQController.preferences.includeList == '' or string.find(myQController.preferences.includeList, devObj.name) ~= nil then
            log.info('Ready to create ' ..devObj.name ..' ('..devObj.serial_number ..')')
            local profileName
            if devObj.device_family == myqDoorFamilyName then
              profileName = doorDeviceProfile
            end
            if devObj.device_family == 'lamp' then
              profileName = lampDeviceProfile
            end

            local metadata = {
              type = 'LAN',
              device_network_id = devObj.serial_number,
              label = devObj.name,
              profile = profileName,
              manufacturer = devObj.device_platform,
              model = myQController.model,
              vendor_provided_label = profileName,
              parent_device_id = myQController.id
            }
            assert (driver:try_create_device(metadata), "failed to create device")
            installedDeviceCount = installedDeviceCount + 1
          else
            --log.info(devObj.name ..' not found in device inclusion list.')
          end
        end
      end
    end

    --Update controller status
    log.info('Refresh successful via ' ..myQController.model ..'. MyQ devices: ' ..myqDeviceCount ..', ST-installed devices: ' ..installedDeviceCount)
    myQController:online()
    local newStatus = 'Connected: ' ..installedDeviceCount ..' devices'
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
        local currentStatus = device:get_latest_state('main', "towertalent27877.myqstatus", "statusText", "unknown")
        if currentStatus ~= offlineStatus then
          log.info('Setting offline' ..currentStatus)
          device:emit_event(myqStatusCap.statusText(offlineStatus))
        end
      end
    end

    --If refresh failed with no response at all, try a UDP search to try and auto detect the server (maybe the IP or port changed)
    log.error('Refresh Failed.')

    if (skipScan ~= 1 and (res_body == nil or code == 404 )) then
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

--Open
function command_handler.open(driver, device)
  log.trace('Sending door open command: ')
  local success = httpUtil.send_lan_command(device.model ..'/' ..device.device_network_id, 'POST', 'control', {command='open', auth=getLoginDetails(driver)})
  if success then
    log.trace('Success. Setting door to opening')
    device:emit_event(caps.doorControl.door('opening'))
    return
  end
  log.error('no response from device')
  device:emit_event(myqStatusCap.statusText('OPEN command failed'))
  return false
end

--Close
function command_handler.close(driver, device)
  log.trace('Sending door close command: ')
  local success = httpUtil.send_lan_command(device.model ..'/' ..device.device_network_id, 'POST', 'control', {command='close', auth=getLoginDetails(driver)})
  if success then
    log.trace('Success. Setting door to closing')
    device:emit_event(caps.doorControl.door('closing'))
    return
  end
  log.error('no response from device')
  device:emit_event(myqStatusCap.statusText('CLOSE command failed'))
  return false
end

--On
function command_handler.on(driver, device)
  log.trace('Sending ON command: ' ..device.vendor_provided_label)
  if (device.vendor_provided_label == doorDeviceProfile) then
    command_handler.open(driver, device)
    return
  end
  local success = httpUtil.send_lan_command(device.model ..'/' ..device.device_network_id, 'POST', 'control', {command='on', auth=getLoginDetails(driver)})

  if success then
    log.trace('Success. Setting switch to on')
    return
    device:emit_event(caps.switch.switch.on())
  end
  log.error('no response from device')
  device:emit_event(myqStatusCap.statusText('ON command failed'))
  return false
end

--Off
function command_handler.off(driver, device)
  log.trace('Sending OFF command: ')
  if (device.vendor_provided_label == doorDeviceProfile) then
    command_handler.close(driver, device)
    return
  end
  local success = httpUtil.send_lan_command(device.model ..'/' ..device.device_network_id, 'POST', 'control', {command='off', auth=getLoginDetails(driver)})

  if success then
    log.trace('Success. Setting switch to off')
    return
    device:emit_event(caps.switch.switch.off())
  end
  log.error('no response from device')
  device:emit_event(myqStatusCap.statusText('OFF command failed'))
  return false
end


function command_handler.getControllerDevice(driver)
  local device_list = driver:get_devices() --Grab existing devices
  for _, device in ipairs(device_list) do
    if device.device_network_id == 'MyQController' then
      log.info('Found controller.' ..device.device_network_id ..device.model)
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
      log.info('Found controller device. MyQ server set to : ' ..device.device_network_id)
      myQController = driver.get_device_info(driver, device.id)
    end
  end
  return {email=myQController.preferences.email, password=myQController.preferences.password}
end

return command_handler