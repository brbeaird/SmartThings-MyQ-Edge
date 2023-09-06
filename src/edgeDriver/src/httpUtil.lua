local neturl = require('net.url')
local json = require('dkjson')
local cosock2 = require "cosock"
local ltn12 = require('ltn12')
local http = cosock2.asyncify "socket.http"
local log = require('log')

local http_handler = {}
http.TIMEOUT = 5

------------------------
-- Send LAN HTTP Request
function http_handler.send_lan_command(url, method, path, body)
    local dest_url = url..'/'..path
    --log.trace('Making ' ..method ..' Call to ' ..dest_url)
    local jsonBody = json.encode(body)
    local res_body = {}

    -- HTTP Request
    local resp, code = http.request({
      url=dest_url,
      method=method,
      headers={
        ['Content-Type'] = 'application/json',
        ["Content-Length"] = #jsonBody;
      },      
      source=ltn12.source.string(jsonBody),
      sink=ltn12.sink.table(res_body)
    })

    -- Handle response
    if res_body == nil then
        log.error('No response from server - ' ..dest_url)
        return false, nil, 'No response from server.'
    elseif code == nil then
        log.error('Non-code response calling: ' ..dest_url ..' - '  ..table.concat(res_body))
        return false, code, res_body
    elseif string.find(code, 'timeout') or string.find(code, 'refused') then
        log.error('Request timed out.' ..dest_url)
        return false, nil, nil
    elseif code ~= 200 then
        log.error('Non-200 response calling: ' ..dest_url ..' - ' ..code ..' - body: ' ..table.concat(res_body))
        return false, code, res_body
    else
      return true, code, res_body
    end
end

  return http_handler