# SmartThings-MyQ-Edge
SmartThings/MyQ Integration via Edge

This provides an integration between SmartThings and MyQ using a LAN bridge server and an Edge driver.

## Installation
  - Add the Edge driver to your SmartThings hub - [click here to add the driver channel](https://bestow-regional.api.smartthings.com/invite/BxlrLZK3GxMP)
  - Decide how you will host the bridge server on your LAN (details on methods below).
    - Using Docker
    - Using a simple executable
  - Once your bridge server is running and connected to MyQ, open the SmartThings mobile app. 
  - Go to devices and click the add button to Add device.
  - Scan for nearby devices
  - You should see your devices automatically added
  
## Running the bridge server with an executable
 - Find the executable [for your OS here](src/server/bin)
 - Download it as well as the config.json file
 - Edit the config.json file to include your MyQ e-mail and password
 - Run the executable. After several seconds, you should see a message indicating a successful connection to MyQ.
 
 
 ## Running the bridge server with Docker (recommended)
  - Dockerhub image can be found here: https://hub.docker.com/r/brbeaird/smartthings-myq-edge
  - Pull the image down: `docker pull brbeaird/smartthings-myq-edge`
  - If using Unraid, enable advanced view, set repository to brbeaird/smartthings-myq-edge and the dockerhub url from the first step
  - Add environment variables: MYQ_EMAIL and MYQ_PASSWORD  
  - Start the container
 
  
### Other Notes
 - The Edge driver and bridge server make use of SSDP for automatic discovery.
 - If the IP address or port of the bridge server changes, the Edge driver will use SSDP to automatically find the server at the new IP/port.
 - The Edge driver pings the bridge server once per minute; this allows the bridge server to store the current IP address/port of the SmartThings hub.
 - The bridge server polls MyQ every 10 seconds to check the status of MyQ devices. If the status is detected to have changed since the last poll, an update will be sent to the Edge driver to instantly update the device in SmartThings. The Edge driver will also occasionally poll the bridge server to cover situations where an update is missed and things get out of sync.



#### Donate/Sponsor:

If you love this integration, feel free to donate or check out the GitHub Sponsor program.

| Platform        | Wallet/Link | QR Code  |
|------------- |-------------|------|
| GitHub Sponsorship      | https://github.com/sponsors/brbeaird |  |
| Paypal      | [![PayPal - The safer, easier way to give online!](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif "Donate")](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=6QH4Y5KCESYPY) |
  
