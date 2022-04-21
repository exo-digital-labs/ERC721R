// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "erc721a/contracts/ERC721A.sol";
import "./IERC721R.sol";
import "./CryptoFightersPotion.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CryptoFightersV2 is
    IERC721R,
    ERC721A,
    ERC2981,
    Ownable,
    ReentrancyGuard
{
    uint256 public maxMintSupply = 8000; // Max mintable supply from presale, public sale, and owner
    uint256 public constant mintPrice = 0.08 ether; // Mint price for presale and public sale
    uint256 public constant mintPriceWithPotion = 0.04 ether; // Mint price for upgrading v1 fighter with potion
    uint256 public maxUserMintAmount = 5; // Max mintable amount per user, includes presale and public sale

    // Sale Status
    bool public publicSaleActive;
    bool public presaleActive;

    uint256 public refundEndTime; // Time from which refunds will no longer be valid
    address public refundAddress; // Address which refunded NFTs will be sent to

    bytes32 public merkleRoot; // Merkle root for presale participants

    mapping(uint256 => bool) public hasRefunded; // users can search if the NFT has been refunded
    mapping(uint256 => bool) public hasRevokedRefund; // users can revoke refund capability for e.g staking, airdrops
    mapping(uint256 => bool) public isOwnerMint; // if the NFT was freely minted by owner

    mapping(uint256 => bool) public hasV1FighterBeenUpgraded; // mapping storing v1 fighters that have been upgraded
    mapping(uint256 => uint256) public v2ToV1Mapping; // mapping connecting v2 fighters to v1 fighters

    string private baseURI;
    IERC721 private immutable cryptoFightersV1;
    CryptoFightersPotion private immutable cryptoFightersPotion;

    modifier notContract() {
        require(!Address.isContract(msg.sender), "No contracts");
        _;
    }

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
    {
        require(presaleActive, "Presale is not active");
        require(msg.value == quantity * mintPrice, "Value");
        require(
            _isAllowlisted(msg.sender, proof, merkleRoot),
            "Not allowlisted"
        );
        require(
            _numberMinted(msg.sender) + quantity <= maxUserMintAmount,
            "Max amount"
        );
        require(_totalMinted() + quantity <= maxMintSupply, "Max mint supply");

        _safeMint(msg.sender, quantity);
    }

    function mintV2FightersPublicSale(uint256 quantity)
        external
        payable
        notContract
    {
        require(publicSaleActive, "Public sale is not active");
        require(msg.value == quantity * mintPrice, "Value");
        require(
            _numberMinted(msg.sender) + quantity <= maxUserMintAmount,
            "Max amount"
        );
        require(_totalMinted() + quantity <= maxMintSupply, "Max mint supply");

        _safeMint(msg.sender, quantity);
    }

    function ownerMint(uint256 quantity, address to) external onlyOwner {
        require(_totalMinted() + quantity <= maxMintSupply, "Max mint supply");
        _safeMint(to, quantity);
        for (uint256 i = _currentIndex - quantity; i < _currentIndex; i++) {
            isOwnerMint[i] = true;
        }
    }

    function refund(uint256[] calldata tokenIds) external nonReentrant {
        require(isRefundGuaranteeActive(), "Refund expired");
        uint256 refundAmount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(msg.sender == ownerOf(tokenId), "Not owner");
            require(!hasRefunded[tokenId], "Already refunded");
            require(
                !isOwnerMint[tokenId],
                "Freely minted NFTs cannot be refunded"
            );
            hasRefunded[tokenId] = true;
            transferFrom(msg.sender, refundAddress, tokenId);

            if (v2ToV1Mapping[tokenId] != 0) {
                refundAmount += mintPriceWithPotion;
            } else {
                refundAmount += mintPrice;
            }
        }

        Address.sendValue(payable(msg.sender), refundAmount);
    }

    function revokeRefund(uint256[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(msg.sender == ownerOf(tokenId), "Not owner");
            hasRevokedRefund[tokenId] = true;
        }
    }

    function getRefundPrice(uint256 tokenId) public view returns (uint256) {
        if (v2ToV1Mapping[tokenId] != 0) {
            return mintPriceWithPotion;
        } else {
            return mintPrice;
        }
    }

    function canBeRefunded(uint256 tokenId) public view returns (bool) {
        return
            !hasRefunded[tokenId] &&
            !isOwnerMint[tokenId] &&
            !hasRevokedRefund[tokenId] &&
            isRefundGuaranteeActive();
    }

    function getRefundGuaranteeEndTime() public view returns (uint256) {
        return refundEndTime;
    }

    function isRefundGuaranteeActive() public view returns (bool) {
        return (block.timestamp <= refundEndTime);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC2981, ERC721A)
        returns (bool)
    {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function withdraw() external onlyOwner {
        require(block.timestamp > refundEndTime, "Refund period not over");
        uint256 balance = address(this).balance;
        Address.sendValue(payable(owner()), balance);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator)
        external
        onlyOwner
    {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
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
