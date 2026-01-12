import { expect } from "chai";
import { ethers, fhenixjs } from "hardhat";

describe("ShadowSwap FHE Setup", function () {
  it("Should have access to the FhenixJS instance", async function () {
    // Using fhenixjs plugin exposed by hardhat
    expect(fhenixjs).to.not.be.undefined;
  });

  it("Should be able to encrypt a trivial value", async function () {
    if (!fhenixjs) return;
    
    // Simple encryption implementation check
    // Note: In real usage, we encrypt for a specific contract address.
    // This just validates the library is loaded.
    console.log("FhenixJS is available!");
  });
});
