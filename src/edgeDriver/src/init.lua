local Driver = require('st.driver')
local caps = require('st.capabilities')

-- local imports
local discovery = require('discovery')
local lifecycles = require('lifecycles')
local commands = require('commands')
local server = require('server')

--------------------
-- Driver definition
local driver =
  Driver(
    'MyQDoor',
    {
      discovery = discovery.start,
      lifecycle_handlers = lifecycles,
      supported_capabilities = {
        caps.doorControl
      },
      capability_handlers = {
        -- Door command handler
        [caps.doorControl.ID] = {
          [caps.doorControl.commands.open.NAME] = commands.open_close,
          [caps.doorControl.commands.close.NAME] = commands.open_close
        },
        -- Refresh command handler
        [caps.refresh.ID] = {
          [caps.refresh.commands.refresh.NAME] = commands.refresh
        }
      }
    }
  )

---------------------------------------
-- Door control for external commands
function driver:open_close(device, open_close)
  if on_off == 'closed' then
    return device:emit_event(caps.doorControl.door.closed())
  end
  return device:emit_event(caps.doorControl.door.open())
end

-----------------------------
-- Initialize Hub server
-- that will open port to
-- allow bidirectional comms.
server.start(driver)

--------------------
-- Initialize Driver
driver:run()
