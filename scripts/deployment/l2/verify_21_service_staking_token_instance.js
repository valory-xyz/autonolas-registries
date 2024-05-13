const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const stakingTokenAddress = parsedData.stakingTokenAddress;

module.exports = [
    stakingTokenAddress
];