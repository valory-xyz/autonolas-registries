const fs = require("fs");
const globalsFile = "globals.json";
const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
const parsedData = JSON.parse(dataFromJSON);
const stakingVerifierAddress = parsedData.stakingVerifierAddress;

module.exports = [
    stakingVerifierAddress
];