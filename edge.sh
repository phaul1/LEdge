#!/bin/bash

# Function to log messages with timestamps
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Update package lists and upgrade existing packages
log "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install necessary dependencies
log "Installing required packages..."
sudo apt install -y curl wget tar screen jq build-essential

# Function to install Go
install_go() {
    log "Installing Go..."
    GO_VERSION="1.20.3"
    wget "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
    rm "go${GO_VERSION}.linux-amd64.tar.gz"
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
    source ~/.profile
    log "Go version: $(go version)"
}

# Check if Go is installed; install if not
if ! command -v go &> /dev/null; then
    install_go
else
    log "Go is already installed: $(go version)"
fi

# Function to install Rust
install_rust() {
    log "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    log "Rust version: $(rustc --version)"
}

# Check if Rust is installed; install if not
if ! command -v rustc &> /dev/null; then
    install_rust
else
    log "Rust is already installed: $(rustc --version)"
fi

# Clone the Light Node repository
REPO_URL="https://github.com/Layer-Edge/light-node.git"
REPO_DIR="$HOME/light-node"

if [ -d "$REPO_DIR" ]; then
    log "Removing existing Light Node repository..."
    rm -rf "$REPO_DIR"
fi

log "Cloning Light Node repository..."
cd "$REPO_DIR" || { log "Failed to enter $REPO_DIR, exiting..."; exit 1; }
git clone "$REPO_URL"

# Install Risc0 Toolchain
log "Installing Risc0 toolchain..."
curl -L https://risczero.com/install | bash
source "$HOME/.cargo/env"
rzup install

# Create .env file with environment variables
ENV_FILE="$REPO_DIR/.env"
log "Setting up environment variables..."

cat <<EOF > "$ENV_FILE"
GRPC_URL=34.31.74.109:9090
CONTRACT_ADDR=cosmos1ufs3tlq4umljk0qfe8k5ya0x6hpavn897u2cnf9k0en9jr7qarqqt56709
ZK_PROVER_URL=https://layeredge.mintair.xyz/
API_REQUEST_TIMEOUT=100
POINTS_API=https://light-node.layeredge.io
EOF

# Prompt user for private key securely
read -s -p "Enter your private key: " PRIVATE_KEY
echo
echo "PRIVATE_KEY=$PRIVATE_KEY" >> "$ENV_FILE"

# Start the Merkle Service
MERKLE_SERVICE_DIR="$REPO_DIR/risc0-merkle-service"
log "Building and running the Merkle Service..."
cd "$MERKLE_SERVICE_DIR" || { log "Failed to enter $MERKLE_SERVICE_DIR, exiting..."; exit 1; }
cargo build && cargo run &
MERKLE_PID=$!

# Wait for the Merkle Service to initialize
sleep 5

# Build and run the Light Node
log "Building the Light Node..."
cd "$REPO_DIR" || { log "Failed to return to $REPO_DIR, exiting..."; exit 1; }
go build

log "Starting the Light Node in a screen session..."
screen -dmS light-node bash -c "cd '$REPO_DIR' && source '$ENV_FILE' && ./light-node; exec bash"

log "Setup completed successfully. The Light Node is running in a detached screen session named 'light-node'."
