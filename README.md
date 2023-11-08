# Sadly, this project has been shut down. MyQ implemented changes that lock down their API to a level that make this integration (and several others) impossible. It was a fun ride while it lasted. See: Meross as a possible alternative.

# SmartThings-MyQ-Edge
SmartThings/MyQ Integration via Edge

This provides an integration between SmartThings and MyQ using a LAN bridge server and an Edge driver.

### Overview
This SmartApp integrates Chamberlain/LiftMaster MyQ doors and plug-in lamp module controllers into SmartThings. It creates a garage door device and/or a light device in your list of Things and allows you to control the device:

* By tapping the device in the SmartThings mobile app
* Automatically by your presence (coming or going) in an automation or other SmartThings rules app
* Via tiles in an ActionTiles dashboard
* By asking Alexa or Google Home to turn the device on (open) or off (close)


### Device and ActionTiles
![Door device](https://i.imgur.com/Yx4uLiZm.png "Door device")
![With ActionTiles](https://i.imgur.com/8BSYtMI.png "With ActionTiles")

## Prerequisites and Network requirements
  - You will need a machine that can continually run the MyQ server bridge application on your network. Examples include: Raspberry Pi, Linux server, Windows desktop, Mac, Unraid server, etc.
  - Your SmartThings hub and the machine running the MyQ server application must be able to reach each other on the same LAN.
  - In most cases, the hub will be able to use SSDP broadcasts to auto-detect the IP address of the server (assuming applicable port mapping, including UDP 1900, has been set up - see detailed instructions below).  
  

## Installation
  - Add the "MyQ Connector" Edge driver to your SmartThings hub - [click here to add the driver channel and install the driver](https://bestow-regional.api.smartthings.com/invite/BxlrLZK3GxMP)
  - Decide how you will host the bridge server on your LAN ([details on methods below](#running-the-bridge-server-with-docker-recommended)).
    - Using Docker
    - Using a simple executable
  - Once your bridge server is running, open the SmartThings mobile app. 
  - Go to devices and click the add button to Add device.
  - Scan for nearby devices
  - You should see the MyQ Controller device added. This can take up to 30 seconds. If it still does not show up, go back out to the "No room assigned" category and see if it got added to the bottom.
  - Go to the MyQ controller device, tap the elipses at the top right, then tap settings  
  - Enter your MyQ email and password
  - ![Door device](https://i.imgur.com/ANZifdsl.png "Door device")
  - You can leave the other settings as-is ([see advanced options below](#advanced-settings-configured-in-the-myq-controller-device))
  - Upon saving, the SmartThings hub will try to find your MyQ server, login, and automatically create devices.
  - If something goes wrong, refresh the controller device and check the status field.
  
  
## Running the bridge server with an executable
 - Find the executable [for your OS here](https://github.com/brbeaird/SmartThings-MyQ-Edge/releases) 
 - Download it
 - Run the executable. After several seconds, you should see a message indicating it is waiting for a connection from the hub.
 - By default, the http server spins up on a random port. If you want to specify one, set the MYQ_SERVER_PORT environment variable on your system.
 
 
 ## Running the bridge server with Docker (recommended)    
  - Check out information here to install Docker: https://docs.docker.com/engine/install/
  - As info: Dockerhub image can be found here: https://hub.docker.com/r/brbeaird/smartthings-myq-edge
  - **Reminder: this docker container must be on the same LAN as the SmartThings hub so they can communicate**
  - Pull the image down: `docker pull brbeaird/smartthings-myq-edge`  
  - Start the container. The command will vary depending on platform (some do not use equal signs), but it will look something like this: `docker run -d --name='smartthings-myq-edge' --network=host 'brbeaird/smartthings-myq-edge:latest'`
  - What this command does: 
    - -d: runs the container in detached mode, so it continually runs in the background
    - --network=host: sets the container to run with "host" mode, which means running without an extra layer between it and the host. This is very important for IP/Port auto-detect
    
  - If you know what you are doing and want to run the container in bridge mode: 
    - Note that with some platforms, UDP broadcast will not work in bridge mode even if you explicitly map the UDP port. If that is the case, autodetection will not work, and you will need to set up the IP/Port manually on the MyQ-Controller device in the SmartThings app.
    - Set the MYQ_SERVER_PORT variable to 8090 (this must be the same port that will be mapped to the host)
    - Map port 8090 TCP, container and host set the same    
    - **Note: This assumes port 8090 is not already in use on your Docker host. You can change it to something else, but be sure to change both the environment variable and the port mapping.**
    - If using IP auto-detection, it is required that the MYQ_SERVER_PORT variable is set to the same port that is mapped to the host. This is because the app needs to know the publicly accessible port is so it can pass that information back to the hub.  
 - For Synology:
  ```
docker run -d --name=myq \
-e PUID=XXX \
-e PGID=XXX \
-e TZ=America/Chicago \
--net=host \
--restart always \
brbeaird/smartthings-myq-edge:latest
```
 - For Raspberry Pi 4:
```
docker run -d --security-opt=seccomp=unconfined --restart='always' --name='smartthings-myq-edge' --network=host 'brbeaird/smartthings-myq-edge:latest'
```
 
## Advanced Settings (configured in the MyQ-Controller device)
 - MyQ Polling Interval: by default, the Edge driver polls MyQ every 10 seconds to check the status of MyQ devices. You can override that interval here. Note that a frequent interval is recommended if you want SmartThings to accurately catch all open/close events.
 - Device include list: if you want to only include certain devices in your MyQ account(s), you can enter the names of which ones you want to be created in SmartThings (separated by a comma)
 - Server IP and Server Port: if you want to bypass auto-detection, you can manually set the MyQ server IP/Port here. This is only recommended for setups where the server has a static IP address as well as the port variable configured.

## Advanced troubleshooting and logging
- To view logs of the edge driver, download the SmartThings CLI here: https://github.com/SmartThingsCommunity/smartthings-cli/releases
- Then, run this command: `smartthings edge:drivers:logcat --hub-address=xxx.xxx.x.x` (entering your hub IP address)
- The CLI should prompt you to login
- When prompted with a list of drivers, choose "MyQ Connector"
 

### Other Notes
 - The MyQ API is generally reliable, but if you watch the polling logs, you will occasionally see random refresh or auth errors. This is expected and should be set up to self-resolve. 


## Special Thanks
Huge shoutout to hjdhjd and the work at [/hjdhjd/myq](https://github.com/hjdhjd/myq) for figuring all of this out from the MyQ side and sharing it out as an incredible library for Node.


## Donate/Sponsor:

If you love this integration, feel free to donate or check out the GitHub Sponsor program.

| Platform        | Wallet/Link | QR Code  |
|------------- |-------------|------|
| GitHub Sponsorship      | https://github.com/sponsors/brbeaird |  |
| Paypal      | [![PayPal - The safer, easier way to give online!](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif "Donate")](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=6QH4Y5KCESYPY) |
  
