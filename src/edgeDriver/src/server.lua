local lux = require('luxure')
local cosock = require('cosock').socket
local json = require('dkjson')
local log = require('log')
local caps = require('st.capabilities')

local hub_server = {}

function hub_server.start(driver)
  local server = lux.Server.new_with(cosock.tcp(), {env='debug'})

  -- Register server
  driver:register_channel_handler(server.sock, function ()
    server:tick()
  end)

  -- Endpoint
  server:post('/updateDeviceState', function (req, res)
    local body = json.decode(req:get_body())
    local device = driver:get_device_info(body.uuid)
    log.trace('Received door status update ' ..body.doorStatus)
    device:emit_event(caps.doorControl.door(body.doorStatus))
    res:send('HTTP/1.1 200 OK')
  end)

  server:post('/ping', function (req, res)
    local body = json.decode(req:get_body())
    log.trace('MyQ server IP ' ..body.ip)
    local device = driver:get_device_info(body.uuid)
    log.trace('device ip ' ..device.model)
    res:send('HTTP/1.1 200 OK')
  end)

  server:listen()
  driver.server = server
end

return hub_server
