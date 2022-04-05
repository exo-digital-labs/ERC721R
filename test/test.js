const { expect } = require("chai");
const { ethers } = require("hardhat");

const parseEther = ethers.utils.parseEther;

let erc721RExample;

const MINT_PRICE = "0.1";

describe("ERC721RExample", function () {
  before(async function () {
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
    const tx = await erc721RExample.publicSaleMint(1, {
      value: parseEther(MINT_PRICE),
    });
  });
});
