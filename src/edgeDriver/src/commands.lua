local caps = require('st.capabilities')
local utils = require('st.utils')
local neturl = require('net.url')
local log = require('log')
local json = require('dkjson')
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
http.TIMEOUT = 5
local ltn12 = require('ltn12')
local ssdp = require('ssdpUtils')

local command_handler = {}

--local customCapability = caps[ 'towertalent27877.lastActivity' ]

---------------
-- Ping command
function command_handler.ping(address, port, device)  
  local ping_data = {ip=address, port=port, ext_uuid=device.id}
  local pingResult = command_handler.send_lan_command(device.model, 'POST', 'ping', ping_data)

  --If ping fails, fall back to SSDP and try to find the bridge via broadcast
  if pingResult == false then
    log.info('===== Ping failed for ' ..device.label ..' attempting auto-update.')
    local res = ssdp.find_device();
    if res ~= nil then            
      local currentBaseUrl = device.model
      local newBaseUrl = res.location:sub(0, res.location:find('/details')-1) ..'/' ..device.device_network_id      
      
      if currentBaseUrl ~= newBaseUrl then
        log.info('===== Updating device URL from: ' ..currentBaseUrl ..' to ' ..newBaseUrl)
        device:try_update_metadata({model = newBaseUrl})
      end
    else
      log.info('===== No MyQ server found.')
      device:offline()
    end  
    return
  end
  device:online()
  return pingResult
  
end
------------------
-- Refresh command
function command_handler.refresh(_, device)  
  local success, data = command_handler.send_lan_command(device.model, 'GET', 'refresh')

    -- Check success
  if success then    
    
    local raw_data = json.decode(table.concat(data)..'}') --ltn12 bug drops last  bracket    

    -- Refresh Door Status
    log.trace('Door ' ..device.label .. ': setting status to ' ..raw_data.doorStatus)
    device:emit_event(caps.doorControl.door(raw_data.doorStatus))

    -- log.trace('Refreshing Last Updated' ..raw_data.lastUpdate)
    -- device:emit_event(customCapability.lastActivity(raw_data.lastUpdate))

  else
    log.error('Door ' ..device.label .. ' : failed to refresh.')        
  end
end


----------------
-- Door commmand
function command_handler.open_close(_, device, command)
  local open_close = command.command
  log.trace('Sending door command: ' ..open_close)

  -- send command via LAN
  local success = command_handler.send_lan_command(device.model, 'POST', 'control', {doorStatus=open_close})

  -- Check if success
  if success then

    if open_close == 'close' then
      log.trace('Success. Setting door to closed')
      return device:emit_event(caps.doorControl.door('closed'))
    end
    log.trace('Success. Setting door to open')
    return device:emit_event(caps.doorControl.door('open'))
  end
  log.error('no response from device')
end

------------------------
-- Send LAN HTTP Request
function command_handler.send_lan_command(url, method, path, body)
  local dest_url = url..'/'..path
  --log.trace('Making ' ..method ..' Call to ' ..dest_url)
  local query = neturl.buildQuery(body or {})
  local res_body = {}

  -- HTTP Request
  local _, code = http.request({
    method=method,
    url=dest_url..'?'..query,
    sink=ltn12.sink.table(res_body),
    headers={
      ['Content-Type'] = 'application/x-www-urlencoded'
    }})

  -- Handle response
  if code == 200 then
    return true, res_body
  else
    log.trace('Error making ' ..method ..' Call to ' ..dest_url ..': Got ' ..code ..' response')    
    return false, nil
  end
  
end

return command_handler