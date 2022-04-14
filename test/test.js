const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

const parseEther = ethers.utils.parseEther;

let owner;
let account2;
let account3;
let erc721RExample;

let blockDeployTimeStamp;

const MINT_PRICE = "0.1";
const FORTY_FIVE_DAYS = 24 * 60 * 60 * 45;

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
  beforeEach(async function () {
    [owner, account2, account3] = await ethers.getSigners();
    const ERC721RExample = await ethers.getContractFactory("ERC721RExample");
    erc721RExample = await ERC721RExample.deploy();
    await erc721RExample.deployed();
    blockDeployTimeStamp = (await erc721RExample.provider.getBlock("latest"))
      .timestamp;

    const saleActive = await erc721RExample.publicSaleActive();
    expect(saleActive).to.be.equal(false);
    await erc721RExample.togglePublicSaleStatus();
    const publicSaleActive = await erc721RExample.publicSaleActive();
    expect(publicSaleActive).to.eq(true);
  });


  it("Owner can toggleRefundCountdown and refundEndTime add `refundPeriod` days.", async function () {
    const beforeRefundEndTime = (
      await erc721RExample.refundEndTime()
    ).toNumber();

    await erc721RExample.provider.send("evm_setNextBlockTimestamp", [
      beforeRefundEndTime,
    ]);

    await erc721RExample.toggleRefundCountdown();

    const afterRefundEndTime = (
      await erc721RExample.refundEndTime()
    ).toNumber();

    expect(afterRefundEndTime).to.be.equal(
      beforeRefundEndTime + FORTY_FIVE_DAYS
    );
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

  it("Freely minted NFTs cannot be refunded", async function () {
    await erc721RExample.ownerMint(1);
    expect(await erc721RExample.isOwnerMint(0)).to.be.equal(true);
    await expect(erc721RExample.refund([0])).to.be.revertedWith(
      "Freely minted NFTs cannot be refunded"
    );
  });

  it("NFT cannot be refunded twice", async function () {
    // update refund address and mint NFT from refund address
    await erc721RExample.setRefundAddress(account3.address);
    await erc721RExample
      .connect(account3)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });

    // other user mint 3 NFTs
    await erc721RExample
      .connect(account2)
      .publicSaleMint(3, { value: parseEther("0.3") });
    expect(
      await erc721RExample.provider.getBalance(erc721RExample.address)
    ).to.be.equal(parseEther("0.4"));

    await erc721RExample.connect(account3).refund([0]);
    await expect(
      erc721RExample.connect(account3).refund([0])
    ).to.be.revertedWith("Already refunded");
  });

  it("check refundEndTime is same with block timestamp in first deploy", async function () {
    const refundEndTime = await erc721RExample.refundEndTime();
    expect(blockDeployTimeStamp + FORTY_FIVE_DAYS).to.be.equal(refundEndTime);
  });

  it("NFT refund should in 45 days", async function () {
    const refundEndTime = await erc721RExample.refundEndTime();

    await erc721RExample
      .connect(account2)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });

    await erc721RExample.provider.send("evm_setNextBlockTimestamp", [
      refundEndTime.toNumber(),
    ]);

    await erc721RExample.connect(account2).refund([0]);
  });

  it("NFT refund expired after 45 days, just plus 1 second", async function () {
    const refundEndTime = await erc721RExample.refundEndTime();

    await erc721RExample
      .connect(account2)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });

    await erc721RExample.provider.send("evm_setNextBlockTimestamp", [
      refundEndTime.toNumber() + 1,
    ]);

    await expect(erc721RExample.connect(account2).refund([0])).to.revertedWith(
      "Refund expired"
    );
  });

  it("owner can not withdraw when `Refund period not over`", async function () {
    await expect(erc721RExample.connect(owner).withdraw()).to.revertedWith(
      "Refund period not over"
    );
  });

  it("can withdraw by owner", async function () {
    const refundEndTime = await erc721RExample.refundEndTime();

    await erc721RExample
      .connect(account2)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });

    // refund period is over, just refundEndTime + 1 second.
    await erc721RExample.provider.send("evm_setNextBlockTimestamp", [
      refundEndTime.toNumber() + 1,
    ]);

    await erc721RExample.provider.send("hardhat_setBalance", [
      owner.address,
      "0x6a94d74f430000", // 0.03 ether
    ]);
    const ownerOriginBalance = await erc721RExample.provider.getBalance(
      owner.address
    );
    // first check the owner balance is less than 0.1 ether
    expect(ownerOriginBalance).to.be.lt(parseEther("0.1"));

    await erc721RExample.connect(owner).withdraw();

    const contractVault = await erc721RExample.provider.getBalance(
      erc721RExample.address
    );
    const ownerBalance = await erc721RExample.provider.getBalance(
      owner.address
    );

    expect(contractVault).to.be.equal(parseEther("0"));
    // the owner origin balance is less than 0.1 ether
    expect(ownerBalance).to.be.gt(parseEther("0.1"));
  });
});
