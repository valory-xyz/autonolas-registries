FROM node:16.7.0 as builder

RUN apt update && apt install jq

COPY . /usr/app
WORKDIR /usr/app
RUN yarn install
RUN npx hardhat compile
RUN cp scripts/mainnet_snapshot.json ./sanpshot.json
ENV SERVICE_CONFIG_HASH="0xd913b5bf68193dfacb941538d5900466c449c9ec8121153f152de2e026fa7f3a"

ENTRYPOINT ["bash", "entrypoint.sh"]

# TODO: introduce second stage (runner)
