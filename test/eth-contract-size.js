const { artifacts } = require("hardhat");
const { expect } = require("chai");

describe("Ethereum EIP-170 contract size guard", function () {
  it("the market-first loan runtime bytecode fits Mainnet EIP-170 (24,576 bytes)", async function () {
    const artifact = await artifacts.readArtifact("CustodiedCollateralLoanPoC");
    const runtimeBytes = (artifact.deployedBytecode.length - 2) / 2;
    expect(runtimeBytes, "on-chain runtime bytes must not exceed EIP-170").to.be.at.most(24576);
    console.log("Optimized CustodiedCollateralLoanPoC deployed runtime bytes:", runtimeBytes);
  });
});
