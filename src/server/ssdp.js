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

process.on('exit', function(){
    server.stop() // advertise shutting down and stop listening
})