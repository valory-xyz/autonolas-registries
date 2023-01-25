FROM node:16.7.0 as builder

RUN apt update -y && apt install jq -y

COPY . /base
WORKDIR /base

RUN yarn install
RUN npx hardhat compile

ENTRYPOINT ["bash", "entrypoint.sh"]
