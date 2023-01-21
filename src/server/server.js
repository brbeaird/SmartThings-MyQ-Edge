var port = process.env.MYQ_SERVER_PORT || 0
const axios = require('axios');
var express = require('express');
var app = express();
app.use(express.json());

const myQApi = require('@hjdhjd/myq'); //Much thanks to hjdhjd for this
var myqEmail;
var myqPassword;
var myq; //Holds MyQ connection object
var myQDeviceMap = {} //Local cache of devices and their statuses

const ssdpId = 'urn:SmartThingsCommunity:device:MyQController' //Used in SSDP auto-discovery


//Set credentials on myq object (these are always passed-in from calls from the ST hub)
function myqLogin(email, password){

  //If password has been updated, set up new API object
  if (email != myqEmail || password != myqPassword){

    //Handle missing info
    if (!email || !password){
      log('Missing username or password.')
      return false;
    }

    //Save it
    log('Got new username/password from hub. Initializing connection.')
    myq = new myQApi.myQApi(email, password);
    myqEmail = email;
    myqPassword = password;
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
      log(`Refresh failed`, 1);
      return res.sendStatus(401);
    }

    //Check for devices
    if (myq.devices && myq.devices.length > 0){
      res.send(myq.devices);
      for (let device of myq.devices){
        myQDeviceMap[device.serial_number] = device;
      }
    }
    else{
      res.status(500).send('No devices found');
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

//Status endpoint for troubleshooting
app.get('/status', async (req, res) => {
  try {
    if (!myq){
      return res.status(200).send('Awaiting login');
    }

    if (!myq.devices || myq.devices.length == 0){
      return res.status(200).send('No devices detected');
    }
    res.send(myq.devices);

  } catch (error) {
    log(`status error: ${error.message}`, 1);
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
  var Server = require('node-ssdp-response').Server
  , server = new Server(
    {
        location: 'http://' + '0.0.0.0' + `:${port}/details`,
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
      let response = await axios.post(hubAddress,
        {
          myqServerPort: port,
          deviceId: headers.DEVICE_ID
        },
        {timeout: 5000})
      log(`Got status ${response.status} from hub.`);
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
