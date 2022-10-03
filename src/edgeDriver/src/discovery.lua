local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local ltn12 = require('ltn12')
local log = require('log')
local config = require('config')
local json = require('dkjson')
local ssdp = require('ssdpUtils')
-- XML modules
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"


-- Fetching device metadata via
-- <device_location>/<device_name>.xml
-- from SSDP Response Location header
local function fetch_device_info(url)
  log.info('===== FETCHING DEVICE METADATA... ' ..url)
  local res = {}
  local _, status = http.request({
    url=url,
    sink=ltn12.sink.table(res)
  })


  if table.concat(res) == '' then
    log.error('===== FAILED TO FETCH METADATA AT: '..url ..status)
    return nil
  end

  log.info('===== res ' ..table.concat(res))
  local raw_data = json.decode(table.concat(res)..'}')


  local deviceList = {}
  for devNumber, devObj in pairs(raw_data.devices) do
     log.info(devObj.deviceType)
      table.insert(deviceList,
        {
          name=devObj.name,
          serialNumber=devObj.serialNumber,
          baseUrl=devObj.baseUrl,
          vendor=devObj.vendor,
          manufacturer=devObj.manufacturer,
          model=url:sub(0, url:find('/details')-1) ..'/' ..devObj.serialNumber,
          location=url:sub(0, url:find('/details')-1) ..'/' ..devObj.serialNumber
        }
      )
  end

  return deviceList

end

local function create_device(driver, device)
  log.info('===== CREATING DEVICE...')
  log.info('===== DEVICE DESTINATION ADDRESS: '..device.location)
  log.info('===== DEVICE DNI/Serial: '..device.serialNumber)
  log.info('===== DEVICE baseURL '..device.baseUrl)
  -- device metadata table
  local metadata = {
    type = config.DEVICE_TYPE,
    device_network_id = device.serialNumber,
    label = device.name,
    profile = config.DEVICE_PROFILE,
    manufacturer = device.manufacturer,
    model = device.location,
    vendor_provided_label = device.vendor
  }
  return driver:try_create_device(metadata)
end

--This is called when user scans for new devices in the mobile app
local disco = {}
function disco.start(driver, opts, cons)
  while true do

    --Scan for MyQ Bridge via SSDP
    local device_res = ssdp.find_device();

    if device_res ~= nil then
      if device_res.location and string.find(device_res.usn, "MyQDoor") then
        log.info('===== MyQ Server FOUND IN NETWORK AT: ' ..device_res.location)

        local devices = fetch_device_info(device_res.location)

        for devNumber, devObj in pairs(devices) do
          log.info('===== creating door ' ..devObj.serialNumber)
          local devResp = create_device(driver, devObj)
        end

        return
      end
    end
    log.error('===== No MyQ Bridge found in network')
  end
end

return disco


