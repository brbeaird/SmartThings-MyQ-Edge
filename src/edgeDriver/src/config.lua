local config = {}

--ST device info.
config.DEVICE_PROFILE='MyQDoor.v1'
config.DEVICE_TYPE='LAN'

-- SSDP Config
config.MC_ADDRESS='239.255.255.250'
config.MC_PORT=1900
config.MC_TIMEOUT=2
config.MSEARCH=table.concat({
  'M-SEARCH * HTTP/1.1',
  'HOST: 239.255.255.250:1900',
  'MAN: "ssdp:discover"',
  'MX: 4',
  'ST: urn:SmartThingsCommunity:device:MyQDoor'
}, '\r\n')
config.SCHEDULE_PERIOD_PING=60
config.SCHEDULE_PERIOD_REFRESH=300
return config
