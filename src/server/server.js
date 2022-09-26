//Grab the port to run on
if (!process.env.PORT){
  process.env['PORT'] = 8125
}
const port = process.env.PORT

const externalConfigFile = './config.json'
const fs = require('fs');
const ssdp = require('./ssdp')
var express = require('express');
var app = express();
const myQApi = require('@hjdhjd/myq');
const axios = require('axios');

var myq;

//Get MyQ config and set up refresh job
const setupMyQ = () => {
  let configFile = fs.readFileSync(externalConfigFile, 'UTF8');
  let myqConfig = JSON.parse(configFile);
  myq = new myQApi.myQApi(myqConfig.email, myqConfig.password);

  setInterval(() => {
    refreshMyQ();
  }, 1000*10);
}

//Local cache of devices and their statuses
var myQDeviceMap = {}
var deviceStatusCache = {}

//Refresh data from MyQ
const refreshMyQ = async () => {
  try {
    await myq.refreshDevices();
    for (let device of myq.devices){
      if (myQDeviceMap[device.serial_number]){
        Object.assign(myQDeviceMap[device.serial_number], device)      
      }
      else{
        myQDeviceMap[device.serial_number] = device;
      }    

      //See if status has changed. If so, try to push to the hub
      if (device.device_family == 'garagedoor' && deviceStatusCache[device.serial_number] && deviceStatusCache[device.serial_number].door_state != device.state.door_state){             
        lastUpdate = new Date(device.state.last_update)
        lastUpdate = lastUpdate.toLocaleString();
        let cacheDevice = myQDeviceMap[device.serial_number]
        if (cacheDevice.hubIp){          
          console.log(`${myQDeviceMap[device.serial_number].name} changed to ${device.state.door_state}`); 
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
  } catch (error) {
    console.log(error.message);    
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
          name: `${device.name}-EDGE`,
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
        console.log(updateMessage);
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
    console.log(`Setting ${myQDeviceMap[req.params.doorId].name} to ${req.query.doorStatus}`);
    myq.execute(myQDeviceMap[req.params.doorId], req.query.doorStatus);
    res.sendStatus(200);
  } catch (error) {
    res.status(500).send(error.message);
  }
})


//Express webserver startup
app.listen(port, function () {
    console.log(`Listening on port ${port}`);
})