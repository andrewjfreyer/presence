# Presence Docker Installation

### Dockerfiles

The `docker` folder contains Dockerfiles for deploying Presence in Docker containers on different architectures. Choose the file that matches your machine's architecture:

**`Dockerfile.amd64`**
<br>
Your typical x64 machine - if you are deploying on a 64-bit laptop or desktop, this is the one you want.

**`Dockerfile.armhf`**
<br>
The Raspberry Pi architecture - use this file if you are deploying on a Raspbery Pi. Confirmed working on:
  - Raspberry Pi Zero W
  - Raspberry Pi 3

### Example Docker Compose Installation

1. Create a file called `docker-compose.yaml` and copy the example template below to the file.

2. Create a local configuration directory on your host machine and create the files `behavior_preferences`, `mqtt_preferences`, and `owner_devices` per the main repository instructions.

3. Change `<YOUR_ARCHITECTURE>` to the Dockerfile extension that matches your architecture.

4. Change `<YOUR_LOCAL_CONFIG>` to the path of the local configuration directory you created in Step 2.


```
version: "3"
services:

  # Presence  --------------------------------------
  presence:
    container_name: presence
    network_mode: "host"
    build:
      context: https://github.com/iicky/presence.git
      dockerfile: docker/Dockerfile.<YOUR_ARCHITECTURE>
    volumes:
      - <YOUR_LOCAL_CONFIG>:/config
    restart: on-failure
```

5. Build and deploy the Docker container by running the following commands:

```
docker-compose build presence
docker-compose up -d presence
```
