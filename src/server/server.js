var port = process.env.PORT || 0
const axios = require('axios');
var express = require('express');
var app = express();
app.use(express.json());

const myQApi = require('@hjdhjd/myq'); //Much thanks to hjdhjd for this
var myq; //Holds MyQ connection object
var myQDeviceMap = {} //Local cache of devices and their statuses

const ssdpId = 'urn:SmartThingsCommunity:device:MyQController' //Used in SSDP auto-discovery


//Set credentials on myq object (these are always passed-in from calls from the ST hub)
function myqLogin(email, password){
  if (!myq){
    if (!email || !password){
      log('Missing username or password.')
      return false;
    }
    log('Got username/password from hub. Initializing connection.')
    myq = new myQApi.myQApi(email, password);
    return true;
  }
  return true;
}

/**Exposed Express routes */

//Gets devices
app.post('/devices', async (req, res) => {
  try {
    if (!myqLogin(req.body.auth.email, req.body.auth.password)){
      return res.sendStatus(401);
    }

    let refreshResult = await myq.refreshDevices();
    if (!refreshResult){
      log(`Refresh error: login failed.`, 1);
      myq = undefined
      return res.sendStatus(401);
    }

    res.send(myq.devices);

    if (myq.devices && myq.devices.length > 0){
      for (let device of myq.devices){
        myQDeviceMap[device.serial_number] = device;
      }
    }

  } catch (error) {
    log(`Refresh error: ${error.message}`, 1);
    res.status(500).send(error.message);
  }
})

//Controls a device
app.post('/:devId/control', async (req, res) => {
  try {
    log(`Setting ${myQDeviceMap[req.params.devId].name} to ${req.body.command}`);
    if (!myqLogin(req.body.auth.email, req.body.auth.password)){
      return res.sendStatus(401);
    }
    let result = await myq.execute(myQDeviceMap[req.params.devId], req.body.command)
    if (result){
      res.sendStatus(200);
    }
    else{
      res.status(500).send('Error sending command. Please try again.')
    }
  } catch (error) {
    res.status(500).send(error.message);
  }
})

//Express webserver startup
let expressApp = app.listen(port, () => {
  port = expressApp.address().port
  log(`HTTP server listening on port ${port}`);
  startSsdp();
})

//Set up ssdp
function startSsdp() {
  var Server = require('./lib/node-ssdp').Server
  , server = new Server(
    {
        location: 'http://' + '' + `:${port}/details`,
        udn: 'uuid:smartthings-brbeaird-myq',
          sourcePort: 1900,
        ssdpTtl: 2
    }
  );
  server.addUSN(ssdpId);
  server.start();
  log(`SSDP server up and listening for broadcasts: ${Object.keys(server._usns)[0]}`)

  //I tweaked ssdp library to bubble up a broadcast event and to then do an http post to the URL
  // this is because this app cannot know its external IP if running as a docker container
  server.on('response', async function (headers, msg, rinfo) {
    try {
      if (headers.ST != ssdpId || !headers.SERVER_IP || !headers.SERVER_PORT){
        return;
      }
      let hubAddress = `http://${headers.SERVER_IP}:${headers.SERVER_PORT}/ping`
      log(`Detected SSDP broadcast. Posting details back to server at ${hubAddress}`)
      await axios.post(hubAddress, {})
    } catch (error) {
        let msg = error.message;
        if (error.response){
          msg += error.response.data
      }
      log(msg, true);
    }
  });
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