// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC721R is ERC721A, Ownable {
    uint256 public immutable collectionSize;
    uint256 public immutable maxBatchSize;
    uint256 public immutable mintPrice;

    uint256 public immutable refundEndTime;
    address public refundAddress;

    mapping(uint256 => bool) public hasRefunded; // users can search if the NFT has been refunded
    mapping(uint256 => bool) public isOwnerMint; // if the NFT was freely minted by owner

    modifier notContract() {
        require(!Address.isContract(msg.sender), "No contract calls");
        _;
    }
    
    constructor(
    string memory name_,
    string memory symbol_,
    uint256 collectionSize_,
    uint256 maxBatchSize_,
    uint256 mintPrice_,
    uint256 refundPeriod_,
    address refundAddress_
    ) ERC721A(name_, symbol_) {
    require(collectionSize_ > 0, "collection must have a nonzero supply");
    require(maxBatchSize_ > 0, "max batch size must be nonzero");
    collectionSize = collectionSize_;
    maxBatchSize = maxBatchSize_;
    mintPrice = mintPrice_;
    refundAddress = refundAddress_;
    refundEndTime = block.timestamp + refundPeriod_;
    }

    function refund(uint256[] calldata tokenIds) external {
        require(refundGuaranteeActive(), "refund expired");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(msg.sender == ownerOf(tokenId), "not token owner");
            require(!hasRefunded[tokenId], "already refunded");
            require(!isOwnerMint[tokenId], "freely minted NFTs cannot be refunded");
            hasRefunded[tokenId] = true;
            transferFrom(msg.sender, refundAddress, tokenId);
        }

        uint256 refundAmount = tokenIds.length * mintPrice;
        Address.sendValue(payable(msg.sender), refundAmount);
    }

    function refundGuaranteeActive() public view returns (bool) {
        return (block.timestamp <= refundEndTime);
    }

    function setRefundAddress(address _refundAddress) external onlyOwner {
        refundAddress = _refundAddress;
    }
}