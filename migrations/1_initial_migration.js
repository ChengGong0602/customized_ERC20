const ChengToken = artifacts.require("ChengToken");

module.exports = function (deployer) {
  deployer.deploy(ChengToken);
};
