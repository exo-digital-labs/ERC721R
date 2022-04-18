const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const { getTree, getProof } = require("../scripts/merkletree");

const parseEther = ethers.utils.parseEther;
const solidityKeccak256 = ethers.utils.solidityKeccak256;

let owner;
let account2;
let account3;
let erc721RExample;

let blockDeployTimeStamp;

let merkleTree;

const MINT_PRICE = "0.1";
const MAX_MINT_SUPPLY = 8000;
const MAX_USER_MINT_AMOUNT = 5;
const REFUND_PERIOD = 24 * 60 * 60 * 45;

const mineSingleBlock = async () => {
  await ethers.provider.send("hardhat_mine", [
    ethers.utils.hexValue(1).toString(),
  ]);
};

async function simulateNextBlockTime(baseTime, changeBy) {
  const bi = BigNumber.from(baseTime);
  await ethers.provider.send("evm_setNextBlockTimestamp", [
    ethers.utils.hexlify(bi.add(changeBy)),
  ]);
  await mineSingleBlock();
}

beforeEach(async function () {
  [owner, account2, account3] = await ethers.getSigners();

  merkleTree = getTree(
    [owner.address, account2.address, account3.address].map((address) =>
      solidityKeccak256(["address"], [address])
    )
  );

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

describe("Aggregation", function () {
  it("Should be able to mint and request a refund", async function () {
    await erc721RExample
      .connect(account2)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });

    const balanceAfterMint = await erc721RExample.balanceOf(account2.address);
    expect(balanceAfterMint).to.eq(1);

    const endRefundTime = await erc721RExample.getRefundGuaranteeEndTime();
    await simulateNextBlockTime(endRefundTime, -10);

    await erc721RExample.connect(account2).refund([0]);

    const balanceAfterRefund = await erc721RExample.balanceOf(account2.address);
    expect(balanceAfterRefund).to.eq(0);

    const balanceAfterRefundOfOwner = await erc721RExample.balanceOf(
      owner.address
    );
    expect(balanceAfterRefundOfOwner).to.eq(1);
  });
});

describe("Check ERC721RExample Constant & Variables", function () {
  it(`Should maxMintSupply = ${MAX_MINT_SUPPLY}`, async function () {
    expect(await erc721RExample.maxMintSupply()).to.be.equal(MAX_MINT_SUPPLY);
  });

  it(`Should mintPrice = ${MINT_PRICE}`, async function () {
    expect(await erc721RExample.mintPrice()).to.be.equal(
      parseEther(MINT_PRICE)
    );
  });

  it(`Should refundPeriod ${REFUND_PERIOD}`, async function () {
    expect(await erc721RExample.refundPeriod()).to.be.equal(REFUND_PERIOD);
  });

  it(`Should maxUserMintAmount ${MAX_USER_MINT_AMOUNT}`, async function () {
    expect(await erc721RExample.maxUserMintAmount()).to.be.equal(
      MAX_USER_MINT_AMOUNT
    );
  });

  it("Should refundEndTime is same with block timestamp in first deploy", async function () {
    const refundEndTime = await erc721RExample.getRefundGuaranteeEndTime();
    expect(blockDeployTimeStamp + REFUND_PERIOD).to.be.equal(refundEndTime);
  });

  it(`Should refundGuaranteeActive = true`, async function () {
    expect(await erc721RExample.isRefundGuaranteeActive()).to.be.true;
  });
});

describe("Owner", function () {
  it("Should be able to mint", async function () {
    await erc721RExample.ownerMint(1);
    expect(await erc721RExample.balanceOf(owner.address)).to.be.equal(1);
    expect(await erc721RExample.ownerOf(0)).to.be.equal(owner.address);
  });

  it("Should not be able to mint when `Max mint supply reached`", async function () {
    await erc721RExample.provider.send("hardhat_setStorageAt", [
      erc721RExample.address,
      "0x0",
      ethers.utils.solidityPack(["uint256"], [MAX_MINT_SUPPLY]), // 8000
    ]);
    await expect(erc721RExample.ownerMint(1)).to.be.revertedWith(
      "Max mint supply reached"
    );
  });

  it("Should not be withdraw when `Refund period not over`", async function () {
    await expect(erc721RExample.connect(owner).withdraw()).to.revertedWith(
      "Refund period not over"
    );
  });

  it("Should be withdraw after refundEndTime", async function () {
    const refundEndTime = await erc721RExample.getRefundGuaranteeEndTime();

    await erc721RExample
      .connect(account2)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });

    await simulateNextBlockTime(refundEndTime, +11);

    await erc721RExample.provider.send("hardhat_setBalance", [
      owner.address,
      "0x8e1bc9bf040000", // 0.04 ether
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

describe("PublicMint", function () {
  it("Should not be able to mint when `Public sale is not active`", async function () {
    await erc721RExample.togglePublicSaleStatus();
    await expect(
      erc721RExample
        .connect(account2)
        .publicSaleMint(1, { value: parseEther(MINT_PRICE) })
    ).to.be.revertedWith("Public sale is not active");
  });

  it("Should not be able to mint when `Not enough eth sent`", async function () {
    await expect(
      erc721RExample.connect(account2).publicSaleMint(1, { value: 0 })
    ).to.be.revertedWith("Not enough eth sent");
  });

  it("Should not be able to mint when `Max mint supply reached`", async function () {
    await erc721RExample.provider.send("hardhat_setStorageAt", [
      erc721RExample.address,
      "0x0",
      ethers.utils.solidityPack(["uint256"], [MAX_MINT_SUPPLY]), // 8000
    ]);
    await expect(
      erc721RExample
        .connect(account2)
        .publicSaleMint(1, { value: parseEther(MINT_PRICE) })
    ).to.be.revertedWith("Max mint supply reached");
  });

  it("Should not be able to mint when `Over mint limit`", async function () {
    await erc721RExample
      .connect(account2)
      .publicSaleMint(5, { value: parseEther("0.5") });
    await expect(
      erc721RExample
        .connect(account2)
        .publicSaleMint(1, { value: parseEther(MINT_PRICE) })
    ).to.be.revertedWith("Over mint limit");
  });
});

describe("PreSaleMint", function () {
  it("Should presale mint merkle tree with valid leaf", async function () {
    const proof = getProof(
      merkleTree.tree,
      solidityKeccak256(["address"], [account3.address])
    );

    await erc721RExample.setMerkleRoot(merkleTree.root);
    await erc721RExample.togglePresaleStatus();
    await erc721RExample.connect(account3).preSaleMint(1, proof, {
      value: parseEther(MINT_PRICE),
    });
    expect(await erc721RExample.balanceOf(account3.address)).to.be.equal(1);
  });

  it("Should not presale mint when `Not on allow list`", async function () {
    await erc721RExample.provider.send("hardhat_setBalance", [
      owner.address,
      "0xffffffffffffffffffff",
    ]);
    // proof from account3
    const proof = getProof(
      merkleTree.tree,
      solidityKeccak256(["address"], [account3.address])
    );

    await erc721RExample.togglePresaleStatus();
    await erc721RExample.setMerkleRoot(merkleTree.root);
    // with account2
    await expect(
      erc721RExample
        .connect(account2)
        .preSaleMint(1, proof, { value: parseEther(MINT_PRICE) })
    ).revertedWith("Not on allow list");
    expect(await erc721RExample.balanceOf(account2.address)).to.be.equal(0);
  });

  it("Should not be mint when `Presale is not active`", async function () {
    const proof = getProof(
      merkleTree.tree,
      solidityKeccak256(["address"], [account2.address])
    );
    await expect(
      erc721RExample.preSaleMint(1, proof, {
        value: parseEther(MINT_PRICE),
      })
    ).to.be.revertedWith("Presale is not active");
  });

  it("Should not be mint when `Value` not enough", async function () {
    await erc721RExample.togglePresaleStatus();
    await erc721RExample.setMerkleRoot(merkleTree.root);

    const proof = getProof(
      merkleTree.tree,
      solidityKeccak256(["address"], [account2.address])
    );

    await expect(
      erc721RExample.preSaleMint(1, proof, { value: 0 })
    ).to.be.revertedWith("Value");
  });

  it("Should not be mint when `Max amount`", async function () {
    await erc721RExample.togglePresaleStatus();
    await erc721RExample.setMerkleRoot(merkleTree.root);

    const proof = getProof(
      merkleTree.tree,
      solidityKeccak256(["address"], [account2.address])
    );
    await erc721RExample
      .connect(account2)
      .preSaleMint(5, proof, { value: parseEther("0.5") });
    await expect(
      erc721RExample
        .connect(account2)
        .preSaleMint(1, proof, { value: parseEther(MINT_PRICE) })
    ).to.be.revertedWith("Max amount");
  });

  it("Should not be mint when `Max mint supply`", async function () {
    await erc721RExample.togglePresaleStatus();
    await erc721RExample.setMerkleRoot(merkleTree.root);
    const proof = getProof(
      merkleTree.tree,
      solidityKeccak256(["address"], [account2.address])
    );
    await erc721RExample.provider.send("hardhat_setStorageAt", [
      erc721RExample.address,
      "0x0",
      ethers.utils.solidityPack(["uint256"], [MAX_MINT_SUPPLY]), // 8000
    ]);
    await expect(
      erc721RExample
        .connect(account2)
        .preSaleMint(1, proof, { value: parseEther(MINT_PRICE) })
    ).to.be.revertedWith("Max mint supply");
  });
});

describe("Refund", function () {
  it("Should be store correct tokenId in refund", async function () {
    await erc721RExample
      .connect(account2)
      .publicSaleMint(5, { value: parseEther("0.5") });
    await erc721RExample.connect(account2).refund([3]);
    expect(await erc721RExample.hasRefunded(3)).to.be.true;
  });

  it("Should be revert `Freely minted NFTs cannot be refunded`", async function () {
    await erc721RExample.ownerMint(1);
    expect(await erc721RExample.isOwnerMint(0)).to.be.equal(true);
    await expect(erc721RExample.refund([0])).to.be.revertedWith(
      "Freely minted NFTs cannot be refunded"
    );
  });

  it("Should be refund NFT in 45 days", async function () {
    const refundEndTime = await erc721RExample.getRefundGuaranteeEndTime();

    await erc721RExample
      .connect(account2)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });

    await erc721RExample.provider.send("evm_setNextBlockTimestamp", [
      refundEndTime.toNumber(),
    ]);

    await erc721RExample.connect(account2).refund([0]);
  });

  it("Should not be refunded when `Not token owner`", async function () {
    await erc721RExample.ownerMint(1);
    expect(await erc721RExample.isOwnerMint(0)).to.be.equal(true);
    await expect(
      erc721RExample.connect(account2).refund([0])
    ).to.be.revertedWith("Not token owner");
  });

  it("Should not be refunded NFT twice `Already refunded`", async function () {
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

  it("Should not be refund NFT expired after 45 days `Refund expired`", async function () {
    const refundEndTime = await erc721RExample.getRefundGuaranteeEndTime();

    await erc721RExample
      .connect(account2)
      .publicSaleMint(1, { value: parseEther(MINT_PRICE) });

    await simulateNextBlockTime(refundEndTime, +1);

    await expect(erc721RExample.connect(account2).refund([0])).to.revertedWith(
      "Refund expired"
    );
  });
});

describe("Toogle", function () {
  it("Should be call toggleRefundCountdown and refundEndTime add `refundPeriod` days.", async function () {
    const beforeRefundEndTime = (
      await erc721RExample.getRefundGuaranteeEndTime()
    ).toNumber();

    await erc721RExample.provider.send("evm_setNextBlockTimestamp", [
      beforeRefundEndTime,
    ]);

    await erc721RExample.toggleRefundCountdown();

    const afterRefundEndTime = (
      await erc721RExample.getRefundGuaranteeEndTime()
    ).toNumber();

    expect(afterRefundEndTime).to.be.equal(beforeRefundEndTime + REFUND_PERIOD);
  });

  it("Should be call togglePresaleStatus", async function () {
    await erc721RExample.togglePresaleStatus();
    expect(await erc721RExample.presaleActive()).to.be.true;
  });

  it("Should be call togglePublicSaleStatus", async function () {
    await erc721RExample.togglePublicSaleStatus();
    expect(await erc721RExample.publicSaleActive()).to.be.false;
  });
});

describe("Setter", function () {
  it("Should be call setRefundAddress", async function () {
    await erc721RExample.setRefundAddress(account2.address);
    expect(await erc721RExample.refundAddress()).to.be.equal(account2.address);
  });

  it("Should be call setMerkleRoot", async function () {
    await erc721RExample.setMerkleRoot(merkleTree.root);
    expect(await erc721RExample.merkleRoot()).to.be.equal(merkleTree.root);
  });
});
