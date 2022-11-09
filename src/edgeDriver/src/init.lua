local Driver = require('st.driver')
local caps = require('st.capabilities')
local log = require('log')
local socket = require('socket')
local config = require('config')
local httpUtil = require('httpUtil')
local cosock = require('cosock').socket
local commands = require('commands')
local lux = require('luxure')
local json = require('dkjson')


-- Create Initial Device
local function discovery_handler(driver, _, should_continue)
  log.debug("Device discovery invoked")

  local myQController = commands.getControllerDevice(driver)
  if myQController == nil then
    local MFG_NAME = 'SmartThings Community'
    local MODEL = 'MyQ-Controller'
    local VEND_LABEL = 'MyQ-Controller'
    local ID = 'MyQController'
    local PROFILE = 'MyQController.v1'

    log.info (string.format('Creating new controller device'))
    local create_device_msg =
    {
      type = "LAN",
      device_network_id = ID,
      label = VEND_LABEL,
      profile = PROFILE,
      manufacturer = MFG_NAME,
      model = '',
      vendor_provided_label = VEND_LABEL,
    }

    assert (driver:try_create_device(create_device_msg), "failed to create device")
  end
  log.debug("Exiting discovery")
end


-- Lifecycle handler to initialize existing devices AND newly discovered devices
local function device_init(driver, device)

  log.debug(device.label .. ": " .. device.device_network_id .. "> INITIALIZING")

  --Set up refresh schedule
  if (device.device_network_id == 'MyQController') then
    commands.refresh(driver, device)
    device.thread:call_on_schedule(
      device.preferences.pollingInterval,
      function ()
        return commands.refresh(driver, device)
      end,
      'refreshTimer')
  end
end


-- Called when device was just created in SmartThings
local function device_added (driver, device)
  log.info(device.id .. ": " .. device.device_network_id .. "> ADDED")
end


--Called when settings are changed
local function handler_infochanged (driver, device, event, args)

  log.debug ('Info changed handler invoked')
  if (device.device_network_id == 'MyQController') then

    --Cancel existing timer
    for timer in pairs(device.thread.timers) do
      device.thread:cancel_timer(timer)
    end

    --Store manually-entered IP/Port info (if applicable)
    if device.preferences.serverIp ~= '' and device.preferences.serverPort ~= '' then
      assert (device:try_update_metadata({model = 'http://' ..device.preferences.serverIp ..':' ..device.preferences.serverPort}), 'failed to update device.')
    end

    --Clear any flags on bad auth
    commands.resetAuth()

    --Set up refresh schedule
    device.thread:call_on_schedule(
      device.preferences.pollingInterval,
      function ()
        return commands.refresh(driver, device)
      end,
      'refreshTimer')
  end

  --Go ahead and refresh
  commands.refresh(driver, device, 1, 1)

end


-- Called when device was deleted via mobile app
local function device_removed(driver, device)
  log.warn(device.id .. ": " .. device.device_network_id .. "> removed")
  for timer in pairs(device.thread.timers) do --Timer should only apply to controller device
    device.thread:cancel_timer(timer)
  end
end


--------------------
-- Driver definition
local driver =
  Driver(
    'myQConnectorDriver',
    {
      discovery = discovery_handler,
      lifecycle_handlers = {
        init = device_init,
        added = device_added,
        infoChanged = handler_infochanged,
        removed = device_removed
      },

      --lifecycle_handlers = lifecycles,
      supported_capabilities = {
        caps.doorControl
      },
      capability_handlers = {
        -- Door command handler
        [caps.doorControl.ID] = {
          [caps.doorControl.commands.open.NAME] = commands.doorControl,
          [caps.doorControl.commands.close.NAME] = commands.doorControl
        },

        -- Lock command handler
        [caps.lock.ID] = {
          [caps.lock.commands.lock.NAME] = commands.lockControl,
          [caps.lock.commands.unlock.NAME] = commands.lockControl
        },

        -- Switch command handler
        [caps.switch.ID] = {
          [caps.switch.commands.on.NAME] = commands.switchControl,
          [caps.switch.commands.off.NAME] = commands.switchControl
        },

        -- Refresh command handler
        [caps.refresh.ID] = {
          [caps.refresh.commands.refresh.NAME] = commands.refresh
        }
      }
    }
  )

  -----------------------------
-- Initialize Hub server (for incoming traffic)
local hub_server = {}

function hub_server.start(driver)
  local server = lux.Server.new_with(cosock.tcp(), {env='debug'})

  -- Register server
  driver:register_channel_handler(server.sock, function ()
    server:tick()
  end)


  --Handles incoming ping from MyQ server when responding to ssdp broadcast
  server:post('/ping', function (req, res)
    local body = json.decode(req:get_body())
    log.info(req:get_headers():serialize())

    --Get the IP/port from the http request
    local myqServerUrl = req.socket:getpeername() ..':' ..body.myqServerPort
    log.info('Incoming ping from ' ..myqServerUrl ..body.deviceId)

    --Respond
    res:send('HTTP/1.1 200 OK')

    --Update URL on controller device
    local myQController = commands.getControllerDevice(driver)
    assert (myQController:try_update_metadata({model = 'http://' ..myqServerUrl}), 'failed to update device.')
  end)

  server:listen()
  log.trace('Server listening on ' ..server.ip ..':' ..server.port)
  driver.server = server
end


hub_server.start(driver)

--------------------
-- Initialize Driver
driver:run()