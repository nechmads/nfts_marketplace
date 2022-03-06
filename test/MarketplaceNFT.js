const { expect } = require("chai");

describe("MarkeplaceNFT contract", function () {
  it("Should be able to deploy token", async function () {
    const [owner] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("DemoERC20");

    const hardhatToken = await Token.deploy();

    const ownerBalance = await hardhatToken.balanceOf(owner.address);
    expect(ownerBalance).to.equal(0);
  });
});
