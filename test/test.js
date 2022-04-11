const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

const parseEther = ethers.utils.parseEther;

let owner;
let account2;
let account3;
let erc721RExample;

const MINT_PRICE = "0.1";

const mineSingleBlock = async () => {
  await ethers.provider.send("hardhat_mine", [
    ethers.utils.hexValue(1).toString(),
  ]);
};
async function simulateNextBlockTime(baseTime,changeBy){
    const bi = BigNumber.from(baseTime);
    await ethers.provider.send("evm_setNextBlockTimestamp", [ethers.utils.hexlify(bi.add(changeBy))])
    await mineSingleBlock();
}
describe("ERC721RExample", function () {
  before(async function () {
    [owner, account2, account3, account4] = await ethers.getSigners();
    const ERC721RExample = await ethers.getContractFactory("ERC721RExample");
    erc721RExample = await ERC721RExample.deploy();
    await erc721RExample.deployed();

    const saleActive = await erc721RExample.publicSaleActive();
    expect(saleActive).to.be.equal(false);
    await erc721RExample.togglePublicSaleStatus();
    const publicSaleActive = await erc721RExample.publicSaleActive();
    expect(publicSaleActive).to.eq(true);
  });


  it("Should be able to mint and request a refund", async function () {
    await erc721RExample
      .connect(account2)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });

    const balanceAfterMint = await erc721RExample.balanceOf(account2.address);
    expect(balanceAfterMint).to.eq(1);

    const endRefundTime = await erc721RExample.getRefundGuaranteeEndTime();
    await simulateNextBlockTime(endRefundTime,-10);

    await erc721RExample.connect(account2).refund([0]);

    const balanceAfterRefund = await erc721RExample.balanceOf(account2.address);
    expect(balanceAfterRefund).to.eq(0);

    const balanceAfterRefundOfOwner = await erc721RExample.balanceOf(
      owner.address
    );
    expect(balanceAfterRefundOfOwner).to.eq(1);
  });

  it("Should disable refund after expiry", async function () {
    await erc721RExample
      .connect(account3)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });

    const balanceAfterMint = await erc721RExample.balanceOf(account3.address);
    expect(balanceAfterMint).to.eq(1);

    const endRefundTime = await erc721RExample.getRefundGuaranteeEndTime();
    await simulateNextBlockTime(endRefundTime,+10);
    await expect(
      erc721RExample.connect(account3).refund([0])
    ).to.be.revertedWith("expired");
  });
});
