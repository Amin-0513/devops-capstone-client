# DevOps Capstone: File Transfer Client

This is the client side of the capstone project. It runs in a Docker container, connects to the server container, receives a file, saves it to the `/clientdata` directory and checks that the file was not changed in transit by comparing SHA-256 checksums.

The client has a web interface built with Streamlit, available at `http://localhost:8501`.

## Features

- Connects to the server over TCP (`server:5000` by default)
- Receives the file together with a JSON header holding the file name, size and checksum
- Saves each received file to `/clientdata` with a timestamp, so earlier files are kept
- Calculates the SHA-256 checksum of the received file and compares it with the server's checksum
- Lists every file stored in the `clientvol` volume

## Project Structure

```
devops-capstone-client/
├── app.py               # Client application (Python + Streamlit)
├── Dockerfile           # Builds the client image
├── docker-compose.yml   # Defines and runs the client container
├── requirements.txt     # Python dependencies
├── images/              # Screenshots
└── README.md
```

## Dockerfile

The image is based on the official `python:3.12-slim` image. It installs the dependencies, copies in the application and declares `/clientdata` as a volume.

```dockerfile
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Volume mount point
RUN mkdir -p /clientdata
VOLUME ["/clientdata"]

# Streamlit default port
EXPOSE 8501

CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--browser.gatherUsageStats=false"]
```

## Docker Compose

The Compose file builds the client, mounts the named volume `clientvol` at `/clientdata` and connects the container to the shared `filenet` network so it can reach the server.

```yaml
services:
  client:
    build: .
    container_name: client
    ports:
      - "8501:8501"
    environment:
      - SERVER_HOST=server
      - SERVER_PORT=5000
    volumes:
      - clientvol:/clientdata
    networks:
      - filenet
    restart: unless-stopped

volumes:
  clientvol:
    name: clientvol

networks:
  filenet:
    external: true
```

## Requirements

```
streamlit==1.39.0
```

## How the Transfer Works

1. The client opens a TCP connection to the server.
2. The server sends one line of JSON followed by the file bytes:
   ```json
   {"filename": "file.txt", "size": 1024, "checksum": "<sha256-hex>"}
   ```
3. The client reads bytes until it has received `size` bytes.
4. The file is saved to `/clientdata/<name>_<timestamp><ext>`.
5. The client calculates the SHA-256 of the received bytes and compares it with `checksum`. It shows a success message if they match and an error if they do not.

## How to Run

### 1. Create the shared network (only if it does not exist yet)

```bash
docker network create filenet
```

### 2. Start the server container

Start the server project first, so that a container named `server` is listening on port 5000 on the `filenet` network.

### 3. Build and start the client

```bash
docker compose up -d --build
```

### 4. Open the client

Go to `http://localhost:8501` and click **Fetch file from server**.

### 5. Check the volume

```bash
docker exec client ls -l /clientdata
docker volume inspect clientvol
```

### 6. Stop the client

```bash
docker compose down
```

## Environment Variables

| Variable      | Default  | Description                  |
|---------------|----------|------------------------------|
| `SERVER_HOST` | `server` | Host name of the server      |
| `SERVER_PORT` | `5000`   | Port the server listens on   |

## Screenshots

### 1. Building and starting the client

Running `docker compose up -d --build` builds the image from `python:3.12-slim`, installs the dependencies, creates the `clientvol` volume and starts the `client` container.

![Building and starting the client](images/01.png)

### 2. Client web interface

The Streamlit interface at `localhost:8501`. The sidebar sets the server host (`server`) and port (`5000`). The table lists the files already saved in `/clientdata`.

![Client web interface](images/02.png)

### 3. File received and checksum verified

After you click **Fetch file from server**, the client receives a 1024-byte file and saves it to `/clientdata`. The expected and actual SHA-256 checksums match, which confirms the file is intact.

![File received and checksum verified](images/03.png)

### 4. Docker volumes

`docker volume ls` shows the `clientvol` volume used by the client, alongside the server's `servervol` volume.

![Docker volumes](images/04.png)
