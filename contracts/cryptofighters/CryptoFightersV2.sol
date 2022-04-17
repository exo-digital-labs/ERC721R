// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "erc721a/contracts/ERC721A.sol";
import "./CryptoFightersPotion.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CryptoFightersV2 is ERC721A, Ownable, ReentrancyGuard {
    uint256 public maxMintSupply = 8000;
    uint256 public constant mintPrice = 0.1 ether;
    uint256 public constant mintPriceWithPotion = 0.05 ether;

    // Sale Status
    bool public publicSaleActive;
    bool public presaleActive;
    uint256 public amountMinted;
    uint256 public refundEndTime;

    address public refundAddress;
    uint256 public maxUserMintAmount;
    mapping(address => uint256) public userMintedAmount;
    bytes32 public merkleRoot;

    mapping(uint256 => bool) public hasV1FighterBeenUpgraded;
    mapping(uint256 => uint256) public v2ToV1Mapping;

    string private baseURI;
    IERC721 private immutable cryptoFightersV1;
    CryptoFightersPotion private immutable cryptoFightersPotion;

    constructor(address _cryptoFightersV1, address _cryptoFightersPotion)
        ERC721A("CryptoFightersAlliance", "CFA")
    {
        cryptoFightersV1 = IERC721(_cryptoFightersV1);
        cryptoFightersPotion = CryptoFightersPotion(_cryptoFightersPotion);
        refundAddress = msg.sender;
    }

    function upgradeV1FightersWithPotion(uint256[] calldata fighterIds)
        external
        payable
        nonReentrant
    {
        uint256 amount = fighterIds.length;
        require(msg.value == amount * mintPriceWithPotion, "Value");
        for (uint256 i = 0; i < amount; i++) {
            uint256 fighterId = fighterIds[i];
            require(
                IERC721(cryptoFightersV1).ownerOf(fighterId) == msg.sender,
                "Not owner"
            );
            require(!hasV1FighterBeenUpgraded[fighterId], "Already upgraded");
            hasV1FighterBeenUpgraded[fighterId] = true;
            v2ToV1Mapping[_currentIndex + i] = fighterId;
        }
        cryptoFightersPotion.burnPotionForAddress(msg.sender, amount);
        _safeMint(msg.sender, amount);
    }

    function mintV2FightersPresale(uint256 quantity, bytes32[] calldata proof)
        external
        payable
        nonReentrant
    {
        require(presaleActive, "Presale is not active");
        require(msg.value == quantity * mintPrice, "Value");
        require(
            _isAllowlisted(msg.sender, proof, merkleRoot),
            "Not whitelisted"
        );
        require(
            userMintedAmount[msg.sender] + quantity <= maxUserMintAmount,
            "Max amount"
        );
        require(amountMinted + quantity <= maxMintSupply, "Max mint supply");

        amountMinted += quantity;
        userMintedAmount[msg.sender] += quantity;

        _safeMint(msg.sender, quantity);
    }

    function mintV2FightersPublicSale(uint256 quantity)
        external
        payable
        nonReentrant
    {
        require(publicSaleActive, "Public sale is not active");
        require(msg.value == quantity * mintPrice, "Value");
        require(
            userMintedAmount[msg.sender] + quantity <= maxUserMintAmount,
            "Max amount"
        );
        require(amountMinted + quantity <= maxMintSupply, "Max mint supply");

        amountMinted += quantity;
        userMintedAmount[msg.sender] += quantity;
        _safeMint(msg.sender, quantity);
    }

    function ownerMint(uint256 quantity) external onlyOwner nonReentrant {
        require(amountMinted + quantity <= maxMintSupply, "Max mint supply");
        _safeMint(msg.sender, quantity);
    }

    function refund(uint256[] calldata tokenIds) external nonReentrant {
        require(isRefundGuaranteeActive(), "Refund expired");
        uint256 refundAmount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(msg.sender == ownerOf(tokenId), "Not owner");
            transferFrom(msg.sender, refundAddress, tokenId);

            if (v2ToV1Mapping[tokenId] != 0) {
                refundAmount += mintPriceWithPotion;
            } else {
                refundAmount += mintPrice;
            }
        }

        Address.sendValue(payable(msg.sender), refundAmount);
    }

    function getRefundGuaranteeEndTime() public view returns (uint256) {
        return refundEndTime;
    }
    function isRefundGuaranteeActive() public view returns (bool) {
        return (block.timestamp <= refundEndTime);
    }

    function withdraw() external onlyOwner {
        require(block.timestamp > refundEndTime, "Refund period not over");
        uint256 balance = address(this).balance;
        Address.sendValue(payable(owner()), balance);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setRefundAddress(address _refundAddress) external onlyOwner {
        refundAddress = _refundAddress;
    }

    function setMerkleRoot(bytes32 _root) external onlyOwner {
        merkleRoot = _root;
    }

    function setBaseURI(string memory uri) external onlyOwner {
        baseURI = uri;
    }

    function toggleRefundCountdown() external onlyOwner {
        refundEndTime = block.timestamp + 45 days;
    }

    function togglePresaleStatus() external onlyOwner {
        presaleActive = !presaleActive;
    }

    function togglePublicSaleStatus() external onlyOwner {
        publicSaleActive = !publicSaleActive;
    }

    function _leaf(address _account) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account));
    }

    function _isAllowlisted(
        address _account,
        bytes32[] calldata _proof,
        bytes32 _root
    ) internal pure returns (bool) {
        return MerkleProof.verify(_proof, _root, _leaf(_account));
    }
}
