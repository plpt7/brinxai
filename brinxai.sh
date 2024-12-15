#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# enable the firewall status
sudo apt-get install ufw
echo "y" | sudo ufw enable
sudo ufw allow 5011
sudo ufw allow 5011/tcp
sudo ufw allow 1194/udp

# Update package list and install dependencies
echo "Updating package list and installing dependencies..."
sudo apt-get update
sudo apt-get install -y curl gnupg lsb-release wget

# Check if GPU is available
echo "Checking GPU availability..."
GPU_AVAILABLE=false
if command -v nvidia-smi &> /dev/null
then
    echo "GPU detected. NVIDIA driver is installed."
    GPU_AVAILABLE=true
else
    echo "No GPU detected or NVIDIA driver not installed."
fi

# pull latest version of the worker node
docker pull admier/brinxai_nodes-worker:latest

# Prompt user for WORKER_PORT
read -p "Enter the port number for WORKER_PORT (default is 5011): " USER_PORT
USER_PORT=${USER_PORT:-5011}

# Create .env file with user-defined WORKER_PORT
echo "Creating .env file..."
cat <<EOF > .env
WORKER_PORT=$USER_PORT
EOF

# Create docker-compose.yml file
echo "Creating docker-compose.yml..."
if [ "$GPU_AVAILABLE" = true ]; then
    cat <<EOF > docker-compose.yml
version: '3.8'

services:
  worker:
    image: admier/brinxai_nodes-worker:latest
    environment:
      - WORKER_PORT=\${WORKER_PORT:-5011}
    ports:
      - "\${WORKER_PORT:-5011}:\${WORKER_PORT:-5011}"
    volumes:
      - ./generated_images:/usr/src/app/generated_images
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - brinxai-network
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
    runtime: nvidia

networks:
  brinxai-network:
    driver: bridge
    name: brinxai-network  # Explicitly set the network name
EOF
else
    cat <<EOF > docker-compose.yml
version: '3.8'

services:
  worker:
    image: admier/brinxai_nodes-worker:latest
    environment:
      - WORKER_PORT=\${WORKER_PORT:-5011}
    ports:
      - "\${WORKER_PORT:-5011}:\${WORKER_PORT:-5011}"
    volumes:
      - ./generated_images:/usr/src/app/generated_images
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - brinxai-network

networks:
  brinxai-network:
    driver: bridge
    name: brinxai-network  # Explicitly set the network name
EOF
fi

# Start Docker containers using docker compose
echo "Starting Docker containers..."
docker compose up -d

# Start Docker Relayer
sudo docker run -d --name brinxai_relay --cap-add=NET_ADMIN -p 1194:1194/udp admier/brinxai_nodes-relay:latest

# Start Docker rembg
sudo docker run -d --name rembg --network brinxai-network --cpus=2 --memory=2048m -p 127.0.0.1:7000:7000 admier/brinxai_nodes-rembg:latest

# Start Docker stable diffusion
sudo docker run -d --name stable-diffusion --network brinxai-network --cpus=2 --memory=2048m -p 127.0.0.1:5050:5050 admier/brinxai_nodes-stabled:latest

# Start Docker upscaler
sudo docker run -d --name upscaler --network brinxai-network --cpus=2 --memory=2048m -p 127.0.0.1:3000:3000 admier/brinxai_nodes-upscaler:latest

# Start Docker text-ui
sudo docker run -d --name text-ui --network brinxai-network --cpus=2 --memory=2048m -p 127.0.0.1:5000:5000 admier/brinxai_nodes-text-ui:latest


echo "Installation and setup completed successfully."
