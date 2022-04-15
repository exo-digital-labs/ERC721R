const { MerkleTree } = require("merkletreejs");
const { ethers } = require("hardhat");

function getTree(elements) {
  const tree = new MerkleTree(elements, ethers.utils.keccak256, {
    sortPairs: true,
  });

  const root = tree.getHexRoot();
  return { tree, root };
}

function getProof(tree, leaf) {
  return tree.getHexProof(leaf);
}

module.exports = { getTree, getProof };
