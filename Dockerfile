# Use the latest stable LTS version of Node.js (v20)
FROM node:20 as builder

# Install jq and clean up
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y jq && \
    rm -rf /var/lib/apt/lists/*

# Copy source files into the image
COPY . /base

# Set working directory
WORKDIR /base

# Install dependencies
RUN yarn install

# Compile contracts using Hardhat
RUN npx hardhat compile

# Define the entrypoint script
ENTRYPOINT ["bash", "entrypoint.sh"]