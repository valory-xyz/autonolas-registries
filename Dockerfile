FROM node:16.7.0 as builder

RUN apt update -y && apt install jq -y

COPY . /usr/app
WORKDIR /usr/app
RUN yarn install
RUN npx hardhat compile
RUN cp scripts/mainnet_snapshot.json ./sanpshot.json

ENTRYPOINT ["bash", "entrypoint.sh"]

# TODO: introduce second stage (runner)
