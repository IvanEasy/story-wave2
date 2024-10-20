#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo -e "Run 'sudo su' to switch to the root user and try again"
    exit 1
fi

if [ "$1" = "help" ]; then
  echo "This is a one-liner for managing the Story node and validator creation"
  echo "-'install <moniker_name>' to install the Story node. Also pass moniker name as the second parameter."
  echo ""
  echo "-'node-update' command to install newer version of Story."
  echo ""
  echo "-'install-snapshot' to install a snapshot and sync your node."
  echo ""
  echo "-'status' to get the status of your node or use 'curl localhost:26657/status | jq'"
  echo ""
  echo "-'node-stop' to stor the story node and story-geth"
  echo ""
  echo "-'logs-story-geth' to check story-geth logs"
  echo ""
  echo "-'logs-story' to check story logs"
  echo ""
  echo "-'remove' to remove the node"
fi

if [ "$1" = "install" ]; then

  # Update and install dependencies
  sudo apt update && sudo apt upgrade -y
  sudo apt install curl git make jq build-essential gcc unzip wget lz4 aria2 -y

  sleep 2

  # Install Story-Geth
  wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.2-ea9f0d2.tar.gz
  tar -xzvf geth-linux-amd64-0.9.2-ea9f0d2.tar.gz
  mkdir -p $HOME/go/bin
  if ! grep -q "$HOME/go/bin" $HOME/.bash_profile; then
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bash_profile
  fi
  sudo cp geth-linux-amd64-0.9.2-ea9f0d2/geth $HOME/go/bin/story-geth
  source $HOME/.bash_profile
  story-geth version

  sleep 1

  # Install Story
  wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.9.13-b4c7db1.tar.gz
  tar -xzvf story-linux-amd64-0.9.13-b4c7db1.tar.gz
  sudo cp story-linux-amd64-0.9.13-b4c7db1/story $HOME/go/bin
  source $HOME/.bash_profile
  story version

  # Initialize the Story node with a moniker
  story init --network iliad --moniker "$2"

  sleep 1

  # Create the systemd service file for story-geth
  sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target

[Service]
User=$USER
ExecStart=$HOME/go/bin/story-geth --iliad --syncmode full
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

  sleep 1

  # Create the systemd service file for story
  sudo tee /etc/systemd/system/story.service > /dev/null <<EOF
[Unit]
Description=Story Consensus Client
After=network.target

[Service]
User=$USER
ExecStart=$HOME/go/bin/story run
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

  sleep 2

  # Start and enable the story-geth service
  sudo systemctl daemon-reload
  sudo systemctl start story-geth
  sudo systemctl enable story-geth

  sleep 2

  # Start and enable the story service
  sudo systemctl daemon-reload
  sudo systemctl start story
  sudo systemctl enable story

  sleep 2

  echo "Node started"
fi
# To launch run ./script install "Node name"

if [ "$1" = "node-update" ]; then
  # Install requirements
  sudo apt update
  sudo apt install golang-go
  sleep 1
  # Stopping the node
  sudo systemctl stop story

  sleep 1

  cd $HOME
  # Downloading new version
  wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.11.0-aac4bfe.tar.gz

  sudo cp $HOME/story-linux-amd64-0.11.0-aac4bfe/story $(which story)

  sleep 1

  # Install Cosmovisor
  source $HOME/.bash_profile
  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest

  sleep 1

  cd $HOME
  wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.11.0-aac4bfe.tar.gz
  tar -xzvf story-linux-amd64-0.11.0-aac4bfe.tar.gz

  sudo mkdir -p $HOME/.story/story/cosmovisor/genesis/bin
  sudo mkdir -p $HOME/.story/story/cosmovisor/upgrades/v0.11.0/bin

  sudo cp $HOME/story-linux-amd64-0.11.0-aac4bfe/story $HOME/.story/story/cosmovisor/upgrades/v0.11.0/bin

  response=$(curl -s https://snapshots2.mandragora.io/story/info.json)

  # Extract the block height from the JSON using jq
  # Assuming the block height is stored under a key like "block_height"
  snapshot_height=$(echo $response | jq -r '.snapshot_height')

  echo '{"name":"v0.11.0","time":"0001-01-01T00:00:00Z","height":$snapshot_height}' > /root/.story/story/cosmovisor/upgrades/v0.11.0/upgrade-info.json

  cat $HOME/.story/story/cosmovisor/upgrades/v0.11.0/bin/story version

  cat $HOME/.story/story/cosmovisor/upgrades/v0.11.0/upgrade-info.json

  sudo cosmovisor add-upgrade v0.11.0 /root/.story/story/cosmovisor/upgrades/v0.11.0/bin/story --force --upgrade-height "$snapshot_height"
  sleep 1

  # Restart the node
  sudo systemctl start story
  sleep 1
  sudo systemctl start story-geth
  sleep 1

  echo "Node updated"

fi

if [ "$1" = "install-snapshot" ]; then
  # Install required dependencies
  sudo apt-get install wget lz4 -y
  sleep 1

  # Stop your story-geth and story nodes
  sudo systemctl stop story-geth
  sudo systemctl stop story

  sleep 5

  # Back up your validator state
  sudo cp $HOME/.story/story/data/priv_validator_state.json $HOME/.story/priv_validator_state.json.backup
  sleep 1

  # Delete previous geth chaindata and story data folders
  sudo rm -rf $HOME/.story/geth/iliad/geth/chaindata
  sudo rm -rf $HOME/.story/story/data
  sleep 1

  # Download story-geth and story snapshots
  wget -O geth_snapshot.lz4 https://snapshots2.mandragora.io/story/geth_snapshot.lz4
  wget -O story_snapshot.lz4 https://snapshots2.mandragora.io/story/story_snapshot.lz4
  sleep 1

  # Decompress story-geth and story snapshots
  lz4 -c -d geth_snapshot.lz4 | tar -xv -C $HOME/.story/geth/iliad/geth
  lz4 -c -d story_snapshot.lz4 | tar -xv -C $HOME/.story/story
  sleep 1

  # Delete downloaded story-geth and story snapshots
  sudo rm -v geth_snapshot.lz4
  sudo rm -v story_snapshot.lz4

  # Restore your validator state
  sudo cp $HOME/.story/priv_validator_state.json.backup $HOME/.story/story/data/priv_validator_state.json

  sleep 5

  # Start your story-geth and story nodes
  sudo systemctl start story-geth
  sleep 1
  sudo systemctl start story
  sleep 1

  echo "Snapshot installed"
fi

if [ "$1" = "status" ]; then
  curl localhost:26657/status | jq
fi

if [ "$1" = "node-stop" ]; then
  sudo systemctl stop story
  sleep 2
  sudo systemctl stop story-geth
  sleep 2
fi

if [ "$1" = "logs-story-geth" ]; then
  sudo journalctl -u story-geth -o cat
fi

if [ "$1" = "logs-story" ]; then
  sudo journalctl -u story -o cat
fi

if [ "$1" = "create-validator" ]; then
  story validator export --export-evm-key
  sleep 1

  story validator create --stake 1000000000000000000 --private-key $(cat $HOME/.story/story/config/private_key.txt | grep "PRIVATE_KEY" | awk -F'=' '{print $2}')
  sleep 1
fi

if [ "$1" = "remove" ]; then
  sudo systemctl stop story-geth
  sudo systemctl stop story
  sleep 1
  sudo systemctl disable story-geth
  sleep 1
  sudo systemctl disable story
  sleep 1
  sudo rm /etc/systemd/system/story-geth.service
  sudo rm /etc/systemd/system/story.service
  sudo systemctl daemon-reload
  sleep 1
  sudo rm -rf $HOME/.story
  sudo rm $HOME/go/bin/story-geth
  sudo rm $HOME/go/bin/story
fi
