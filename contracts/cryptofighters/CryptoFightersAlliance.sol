// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721A.sol";
import "./IERC721R.sol";
import "./CryptoFightersPotion.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CryptoFightersAlliance is
    IERC721R,
    ERC721A,
    ERC2981,
    Ownable
{
    uint256 public maxMintSupply = 8000; // Max mintable supply from presale, public sale, and owner
    uint256 public constant mintPrice = 0.08 ether; // Mint price for presale and public sale
    uint256 public constant mintPriceWithPotion = 0.04 ether; // Mint price for upgrading v1 fighter with potion
    uint256 public maxUserMintAmount = 5; // Max mintable amount per user, includes presale and public sale
    uint256 public mintedAmount; // Tracks minted amount excluding potion upgrades

    // Sale Status
    bool public publicSaleActive;
    bool public presaleActive;

    uint256 public refundEndTime; // Time from which refunds will no longer be valid
    address public refundAddress; // Address which refunded NFTs will be sent to

    bytes32 public merkleRoot; // Merkle root for presale participants

    mapping(address => uint256) public numberMinted; // total user amount minted in public sale and presale
    mapping(uint256 => bool) public hasRefunded; // users can search if the NFT has been refunded
    mapping(uint256 => bool) public hasRevokedRefund; // users can revoke refund capability for e.g staking, airdrops
    mapping(uint256 => bool) public isOwnerMint; // if the NFT was freely minted by owner

    mapping(uint256 => bool) public hasV1FighterBeenUpgraded; // mapping storing v1 fighters that have been upgraded
    mapping(uint256 => uint256) public v2ToV1Mapping; // mapping connecting v2 fighters to v1 fighters

    string private baseURI;
    IERC721 private immutable cryptoFightersV1;
    CryptoFightersPotion private immutable cryptoFightersPotion;

    /**
     * @dev triggered after owner withdraws funds
     */
    event Withdrawal(address to, uint amount);

    /**
     * @dev triggered after owner switches the refund address
     */
    event SetRefundAddress(address refundAddress);

    /**
     * @dev triggered after the owner sets the allowlist merkle root
     */
    event SetMerkleRoot(bytes32 root);

    /**
     * @dev triggered after the owner sets the base uri
     */
    event SetBaseUri(string uri);

    /**
     * @dev triggered after the refund countdown begins
     */
    event ToggleRefundCountdown(uint refundEndTime);

    /**
     * @dev triggered after the presale status in enabled/disabled
     */
    event TogglePresaleStatus(bool presaleStatus);

    /**
     * @dev triggered after the public sale status in enabled/disabled
     */
    event TogglePublicSaleStatus(bool publicSaleStatus);

    /**
     * @dev Constructor that is used to set state variables and toggle refund countdown
     */
    constructor(address _cryptoFightersV1, address _cryptoFightersPotion)
        ERC721A("CryptoFightersAlliance", "CFA")
    {
        cryptoFightersV1 = IERC721(_cryptoFightersV1);
        cryptoFightersPotion = CryptoFightersPotion(_cryptoFightersPotion);
        refundAddress = msg.sender;
        toggleRefundCountdown();
    }

    /**
     * @dev Allows users to upgrade their V1 Fighters with a potion
     *
     * Requirements:
     *
     * - Value sent must be correct
     * - Caller must own the V1 Fighter they're upgrading
     * - The V1 Fighter must not have been upgraded already
     * - The caller must have enough potions to burn
     */
    function upgradeV1FightersWithPotion(uint256[] calldata fighterIds)
        external
        payable
    {
        uint256 amount = fighterIds.length;
        require(msg.value == amount * mintPriceWithPotion, "Bad value");
        for (uint256 i = 0; i < amount; i++) {
            uint256 fighterId = fighterIds[i];
            require(
                IERC721(cryptoFightersV1).ownerOf(fighterId) == msg.sender,
                "Not owner"
            );
            require(!hasV1FighterBeenUpgraded[fighterId], "Upgraded");
            hasV1FighterBeenUpgraded[fighterId] = true;
            v2ToV1Mapping[_currentIndex + i] = fighterId;
        }
        cryptoFightersPotion.burnPotionForAddress(msg.sender, amount);
        _safeMint(msg.sender, amount);
    }

    /**
     * @dev Allows specific users to mint during presale
     *
     * Requirements:
     *
     * - Presale must be active
     * - Value sent must be correct
     * - Caller must be in allowlist
     * - Total user amount minted cannot be above max user mint amount
     * - Total number minted cannot be above max mint supply
     */
    function mintPresale(uint256 quantity, bytes32[] calldata proof)
        external
        payable
    {
        require(presaleActive, "Not active");
        require(msg.value == quantity * mintPrice, "Bad value");
        require(
            _isAllowlisted(msg.sender, proof, merkleRoot),
            "Allowlist"
        );
        require(
            numberMinted[msg.sender] + quantity <= maxUserMintAmount,
            "Max amount"
        );
        require(mintedAmount + quantity <= maxMintSupply, "Max supply");
        numberMinted[msg.sender] += quantity;
        mintedAmount += quantity;

        _safeMint(msg.sender, quantity);
    }

    /**
     * @dev Allows anyone to mint during public sale
     *
     * Requirements:
     *
     * - Caller cannot be contract
     * - Public sale must be active
     * - Value sent must be correct
     * - Total user amount minted cannot be above max user mint amount
     * - Total number minted cannot be above max mint supply
     */
    function mint(uint256 quantity)
        external
        payable
    {
        require(!Address.isContract(msg.sender), "No contracts");
        require(publicSaleActive, "Not active");
        require(msg.value == quantity * mintPrice, "Bad value");
        require(
            numberMinted[msg.sender] + quantity <= maxUserMintAmount,
            "Max amount"
        );
        require(mintedAmount + quantity <= maxMintSupply, "Max supply");
        numberMinted[msg.sender] += quantity;
        mintedAmount += quantity;

        _safeMint(msg.sender, quantity);
    }

    /**
     * @dev Allows owner to mint. NFTs minted by the owner cannot be refunded since they were not paid for.
     *
     * Requirements:
     *
     * - The caller must be the owner
     * - The new total supply cannot 
     */
    function ownerMint(address to, uint256 quantity) external onlyOwner {
        require(mintedAmount + quantity <= maxMintSupply, "Max supply");
        mintedAmount += quantity;
        _safeMint(to, quantity);
        for (uint256 i = _currentIndex - quantity; i < _currentIndex; i++) {
            isOwnerMint[i] = true;
        }
    }

    /**
     * @dev Refunds all tokenIds, sends them to refund address and sends caller corresponding ETH
     *
     * Requirements:
     *
     * - The caller must own all token ids
     * - The token must be refundable - check `canBeRefunded`.
     */
    function refund(uint256[] calldata tokenIds) external override {
        require(isRefundGuaranteeActive(), "Expired");
        uint256 refundAmount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(msg.sender == ownerOf(tokenId), "Not owner");
            require(!hasRevokedRefund[tokenId], "Revoked");
            require(!hasRefunded[tokenId], "Refunded");
            require(
                !isOwnerMint[tokenId],
                "Owner mint"
            );
            hasRefunded[tokenId] = true;
            transferFrom(msg.sender, refundAddress, tokenId);

            uint256 tokenAmount = getRefundPrice(tokenId);

            refundAmount += tokenAmount;
            emit Refund(msg.sender, tokenId, tokenAmount);
        }

        Address.sendValue(payable(msg.sender), refundAmount);
    }

    /**
     * @dev Returns refund price of a given token id, differs whether minted with potion or not
     *
     * Requirements:
     *
     * - `tokenIds` must be owned by caller
     */
    function revokeRefund(uint256[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(msg.sender == ownerOf(tokenId), "Owner");
            hasRevokedRefund[tokenId] = true;
        }
    }

    /**
     * @dev Returns refund price of a given token id, differs whether minted with potion or not
     */
    function getRefundPrice(uint256 tokenId) public view override returns (uint256) {
        if (v2ToV1Mapping[tokenId] != 0) {
            return mintPriceWithPotion;
        } else {
            return mintPrice;
        }
    }

    /**
     * @dev Returns true if the given token id can be refunded. Only occurs if the token id has not been
     * refunded, hasn't been minted by the owner, hasn't been revoked and refund end time hasn't passed
     */
    function canBeRefunded(uint256 tokenId) public view returns (bool) {
        return
            !hasRefunded[tokenId] &&
            !isOwnerMint[tokenId] &&
            !hasRevokedRefund[tokenId] &&
            isRefundGuaranteeActive();
    }

    /**
     * @dev Returns the timestamp from which refunds can no longer occur
     */
    function getRefundGuaranteeEndTime() public view override returns (uint256) {
        return refundEndTime;
    }

    /**
     * @dev Returns true if refund end time has not passed
     */
    function isRefundGuaranteeActive() public view override returns (bool) {
        return (block.timestamp <= refundEndTime);
    }

    /**
     * @inheritdoc ERC2981
     */
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

    /**
     * @dev Withdraws the funds to the owner
     *
     * Requirements:
     *
     * - `refundEndTime` must have passed
     */
    function withdraw() external onlyOwner {
        require(block.timestamp > refundEndTime, "Refund period not over");
        uint256 balance = address(this).balance;
        Address.sendValue(payable(owner()), balance);
        emit Withdrawal(owner(), balance);
    }

    /**
     * @dev Sets the royalty information that all ids in this contract will default to.
     *
     * Requirements:
     *
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator)
        external
        onlyOwner
    {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @dev Sets the royalty information for a specific token id, overriding the global default.
     *
     * Requirements:
     *
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    /**
     * @dev Resets royalty information for the token id back to the global default.
     */
    function resetTokenRoyalty(uint256 tokenId) external onlyOwner {
        _resetTokenRoyalty(tokenId);
    }

    /**
     * @dev Returns base uri
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Sets address where refunded NFTs will be sent to
     */
    function setMaxUserMintAmount(uint _maxUserMintAmount) external onlyOwner {
        maxUserMintAmount = _maxUserMintAmount;
    }

    /**
     * @dev Sets address where refunded NFTs will be sent to
     */
    function setRefundAddress(address _refundAddress) external onlyOwner {
        refundAddress = _refundAddress;
        emit SetRefundAddress(_refundAddress);
    }

    /**
     * @dev Sets merkle root for allowlist
     */
    function setMerkleRoot(bytes32 _root) external onlyOwner {
        merkleRoot = _root;
        emit SetMerkleRoot(_root);
    }

    /**
     * @dev Sets base uri
     */
    function setBaseURI(string memory uri) external onlyOwner {
        baseURI = uri;
        emit SetBaseUri(uri);
    }

    /**
     * @dev Toggles refund countdown of 45 days, called in constructor
     */
    function toggleRefundCountdown() public onlyOwner {
        refundEndTime = block.timestamp + 45 days;
        emit ToggleRefundCountdown(refundEndTime);
    }

    /**
     * @dev Toggles presale status (enables/disables)
     */
    function togglePresaleStatus() external onlyOwner {
        presaleActive = !presaleActive;
        emit TogglePresaleStatus(presaleActive);
    }

    /**
     * @dev Toggles public sale status (enables/disables)
     */
    function togglePublicSaleStatus() external onlyOwner {
        publicSaleActive = !publicSaleActive;
        emit TogglePublicSaleStatus(publicSaleActive);
    }

    /**
     * @dev Returns keccak256 hash of encoded address
     */
    function _leaf(address _account) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account));
    }

    /**
     * @dev Returns true if valid proof is provided for _account belonging in merkle tree `_root`
     */
    function _isAllowlisted(
        address _account,
        bytes32[] calldata _proof,
        bytes32 _root
    ) internal pure returns (bool) {
        return MerkleProof.verify(_proof, _root, _leaf(_account));
    }
}
