const { expect } = require("chai");
const { ethers } = require("hardhat");
const { expectRevert } = require("@openzeppelin/test-helpers");

const parseEther = ethers.utils.parseEther;

let owner;
let account2;
let erc721RExample;

const MINT_PRICE = "0.1";

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
    expect(publicSaleActive).to.be.equal(true);
  });

  it("Should be able to deploy", async function () {});

  it("Should be able to mint and request a refund", async function () {
    await erc721RExample
      .connect(account2)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });
    const balanceAfterMint = await erc721RExample.balanceOf(account2.address);
    expect(balanceAfterMint).to.be.equal(1);
    await erc721RExample.connect(account2).refund([0]);
    const balanceAfterRefund = await erc721RExample.balanceOf(account2.address);
    expect(balanceAfterRefund).to.be.equal(0);
    const balanceAfterRefundOfOwner = await erc721RExample.balanceOf(
      owner.address
    );
    expect(balanceAfterRefundOfOwner).to.be.equal(1);
  });

  it("Freely minted NFTs cannot be refunded", async function () {
    await erc721RExample.ownerMint(1);
    expect(await erc721RExample.isOwnerMint(1)).to.be.equal(true);
    await expectRevert(
      erc721RExample.refund([1]),
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

    await erc721RExample.connect(account3).refund([2]);
    await expectRevert(
      erc721RExample.connect(account3).refund([2]),
      "Already refunded"
    );
  });
});
