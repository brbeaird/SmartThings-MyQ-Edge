const port = process.env.PORT || 0
const externalConfigFile = './config.json'
const fs = require('fs');
var express = require('express');
var app = express();
const myQApi = require('@hjdhjd/myq');
const axios = require('axios');

var myq;

//Get MyQ config and set up refresh job
const setupMyQ = () => {

  //Check for a config file if environment variables not present
  if (!process.env.MYQ_EMAIL || !process.env.MYQ_PASSWORD){
    try {
      if (!process.env.MYQ_EMAIL){
        log('No environment variable found for MYQ_EMAIL');
      }

      if (!process.env.MYQ_PASSWORD){
        log('No environment variable found for MYQ_PASSWORD');
      }

      log(`Checking for config file ${externalConfigFile}`);

      let configFile = fs.readFileSync(externalConfigFile, 'UTF8');
      let myqConfig = JSON.parse(configFile);

      if (!myqConfig){
        log(`Found config file but could not parse it. Verify JSON formatting`, true);
        process.exit();
      }

      else if (!myqConfig.MYQ_EMAIL || !myqConfig.MYQ_PASSWORD){
        log(`Found config file but MYQ_EMAIL and/or MYQ_PASSWORD value is missing`, true);
        process.exit();
      }

      else{
        log(`Loaded config file successfully`);
      }

      process.env['MYQ_EMAIL'] = myqConfig.MYQ_EMAIL;
      process.env['MYQ_PASSWORD'] = myqConfig.MYQ_PASSWORD;

    } catch (error) {
      log(`Error retrieving login information: ${error.message}`, true);
      process.exit();
    }
  }

  if (!process.env['MYQ_EMAIL'] && !process.env['MYQ_EMAIL']){
    console.error(`MyQ credentials must be specified either MYQ_EMAIL and MYQ_PASSWORD env variables or within the config.json file`);
    process.exit();
  }

  //All good. Send it
  startSsdp();
  myq = new myQApi.myQApi(process.env.MYQ_EMAIL, process.env.MYQ_PASSWORD);

  refreshMyQ(true);
  setInterval(() => {
    refreshMyQ();
  }, 1000*10);
}

//Local cache of devices and their statuses
var myQDeviceMap = {}
var deviceStatusCache = {}

//Refresh data from MyQ
const refreshMyQ = async (firstRun = false) => {
  try {
    await myq.refreshDevices();
    for (let device of myq.devices){
      if (device.device_family == 'garagedoor'){
        if (myQDeviceMap[device.serial_number]){
          Object.assign(myQDeviceMap[device.serial_number], device)
        }
        else{
          myQDeviceMap[device.serial_number] = device;
        }

        //See if status has changed. If so, try to push to the hub
        if (deviceStatusCache[device.serial_number] && deviceStatusCache[device.serial_number].door_state != device.state.door_state){
          lastUpdate = new Date(device.state.last_update)
          lastUpdate = lastUpdate.toLocaleString();
          let cacheDevice = myQDeviceMap[device.serial_number]
          if (cacheDevice.hubIp){
            log(`${myQDeviceMap[device.serial_number].name} changed to ${device.state.door_state}`);
            await axios.post(`http://${cacheDevice.hubIp}:${cacheDevice.hubPort}/updateDeviceState`,
                {
                  uuid: cacheDevice.hubDeviceUuid,
                  doorStatus: device.state.door_state,
                  lastUpdate: lastUpdate
                })
          }
        }
        deviceStatusCache[device.serial_number] = device.state;
      }
    }
    if (firstRun){
      log(`Found ${Object.keys(myQDeviceMap).length} devices compatible with SmartThings. Waiting for discovery...`)
    }
  } catch (error) {
    log(error.message);
  }
}

setupMyQ();

/**EXPRESS ROUTES */

//Called during discovery
app.get('/details', (req, res) => {
  try {
    let devArray = [];

    for (let device of myq.devices){
      if (device.device_family == 'garagedoor'){
        devArray.push({
          name: device.name,
          baseUrl: `${require('ip').address()}:${port}`,
          vendor: 'MyQ',
          manufacturer: device.device_platform,
          model: device.device_type,
          serialNumber: device.serial_number,
          status: device.state.door_state,
          lastUpdate: device.state.last_update
        })
      }
    }
    let result = {devices: devArray}
    res.send(result);
  } catch (error) {
    res.status(500).send(error.message);
  }
})

//Called by the hub fairly frequently
app.post('/:doorId/ping', (req, res) => {
  try {
    //If we know about this door, link hub network info with iti
    if (myQDeviceMap[req.params.doorId]){
      let prevHubAddress = myQDeviceMap[req.params.doorId].hubIp + ':' + myQDeviceMap[req.params.doorId].hubPort
      let hubAddress = req.query.ip + ':' + req.query.port;

      //Log this action to console
      if (prevHubAddress != hubAddress){
        let updateMessage = `Door ${req.params.doorId}: Updating hub address to ${hubAddress}.`
        if (prevHubAddress != 'undefined:undefined'){
          updateMessage += ` (Previously ${prevHubAddress})`
        }
        log(updateMessage);
      }
      myQDeviceMap[req.params.doorId].hubIp = req.query.ip;
      myQDeviceMap[req.params.doorId].hubPort = req.query.port;
      myQDeviceMap[req.params.doorId].hubDeviceUuid = req.query.ext_uuid;
    }
    res.sendStatus(200);
  } catch (error) {
    res.status(500).send(error.message);
  }
})


//Called by the hub less frequently, mostly as a fallback to keep things in sync
app.get('/:doorId/refresh', (req, res) => {
  try {
    let lastUpdate;
    if (myQDeviceMap[req.params.doorId]?.state.last_update){
      lastUpdate = new Date(myQDeviceMap[req.params.doorId].state.last_update)
      lastUpdate = lastUpdate.toLocaleString();
    }
    let cache = {
      doorStatus: myQDeviceMap[req.params.doorId].state.door_state,
      lastUpdate: lastUpdate
    }
    res.send(cache)
  } catch (error) {
    res.status(500).send(error.message);
  }
})


//Called by the hub to send commands to doors
app.post('/:doorId/control', (req, res) => {
  try {
    log(`Setting ${myQDeviceMap[req.params.doorId].name} to ${req.query.doorStatus}`);
    myq.execute(myQDeviceMap[req.params.doorId], req.query.doorStatus);
    res.sendStatus(200);
  } catch (error) {
    res.status(500).send(error.message);
  }
})


//Express webserver startup
let expressApp = app.listen(port, () => {
    log(`HTTP server listening on port ${expressApp.address().port}`);
})

function startSsdp() {
  var Server = require('node-ssdp').Server
  , server = new Server(
    {
        location: 'http://' + require('ip').address() + `:${process.env.PORT}/details`,
        udn: 'uuid:smartthings-brbeaird-myq',
          sourcePort: 1900,
        ssdpTtl: 2
    }
  );

  server.addUSN('urn:SmartThingsCommunity:device:MyQDoor');

  // start the server
  server.start();
  log('SSDP server up.')

  process.on('exit', function(){
      server.stop() // advertise shutting down and stop listening
  })
}

//Logging with timestamp
function log(msg, isError) {
  let dt = new Date().toLocaleString();
  if (!isError) {
    console.log(dt + ' | ' + msg);
  }
  else{
    console.error(dt + ' | ' + msg);
  }
}