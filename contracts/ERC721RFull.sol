// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC721RExample is ERC721A, Ownable {
    uint256 public constant maxMintSupply = 8000;
    uint256 public constant refundPeriod = 45 days;

    // === NEW === 
    // (Optional) Users can't refund their NFT's instantly.
    // After some time (in this scenario 30 days),
    // they'll be able to refund before refundPeriod ends.
    // (in this scenario, users will have 15 more days to refund after refundLock expired.)
    uint256 public constant refundLock = 30 days;
    // I thought the project owner would be happy if ...
    // ... he can set mintPrice specially for another cases (presale, publicsale etc..)
    uint256 public mintPrice = 0.1 ether;
    // ===========

    // Sale Status
    bool public publicSaleActive = true;
    bool public presaleActive;
    uint256 public amountMinted;
    uint256 public refundEndTime;

    address public refundAddress;
    uint256 public maxUserMintAmount = 5;
    mapping(address => uint256) public userMintedAmount;
    // === NEW ===
    mapping(uint256 => uint256) public tokenPrices;
    // ===========
    bytes32 public merkleRoot;

    string private baseURI;

    modifier notContract() {
        require(!Address.isContract(msg.sender), "No contracts");
        _;
    }

    constructor() ERC721A("ERC721RExample", "ERC721R") {
        refundAddress = msg.sender;
        toggleRefundCountdown();
    }

    // === NEW ===
    function setTokenPrices(uint256 quantity) private {
        for(uint256 i = 0; i < quantity; i++){
            tokenPrices[totalSupply() + i ] = mintPrice;
        }
    }

    function refundLockActive() public view returns (bool) {
        return (block.timestamp >= refundLock);
    }
    // ========

    function preSaleMint(uint256 quantity, bytes32[] calldata proof)
        external
        payable
        notContract
    {
        require(presaleActive, "Presale is not active");
        require(msg.value == quantity * mintPrice, "Value");
        require(
            _isAllowlisted(msg.sender, proof, merkleRoot),
            "Not on allow list"
        );
        require(
            userMintedAmount[msg.sender] + quantity <= maxUserMintAmount,
            "Max amount"
        );
        require(amountMinted + quantity <= maxMintSupply, "Max mint supply");

        amountMinted += quantity;
        userMintedAmount[msg.sender] += quantity;

        // === NEW ===
        setTokenPrices(quantity);
        // ==========

        _safeMint(msg.sender, quantity);
    }

    function publicSaleMint(uint256 quantity) external payable notContract {
        require(publicSaleActive, "Public sale is not active");
        require(msg.value >= quantity * mintPrice, "Not enough eth sent");
        require(
            userMintedAmount[msg.sender] + quantity <= maxUserMintAmount,
            "Over mint limit"
        );
        require(
            amountMinted + quantity <= maxMintSupply,
            "Max mint supply reached"
        );

        // === NEW ===
        setTokenPrices(quantity);
        // ===========

        amountMinted += quantity;
        userMintedAmount[msg.sender] += quantity;
        _safeMint(msg.sender, quantity);
    }

    function ownerMint(uint256 quantity) external onlyOwner {
        require(
            amountMinted + quantity <= maxMintSupply,
            "Max mint supply reached"
        );

        // === NEW ===
        setTokenPrices(quantity);
        // ===========

        _safeMint(msg.sender, quantity);
    }

    function refund(uint256[] calldata tokenIds) external {
        // === NEW ===
        // refundAddress can call this function over and over again and take all the funds from contract.
        // Because everytime refundAddress call this function, tokens are transfering to himself again.
        // And then, he will be able to call this refund function with same token Id over and over again ...
        // ... until he withdraw all the funds from contract.
        require(msg.sender != refundAddress, "Can't refund to refundAddress");
        // (Optional) User is need to wait at least a few days (in this scenario 30 days) to call this function.
        require(!refundLockActive(), "Refunds will be able in 30 days");
        // ===========
        require(refundGuaranteeActive(), "Refund expired");
        uint256 refundAmount = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(msg.sender == ownerOf(tokenId), "Not token owner");
            transferFrom(msg.sender, refundAddress, tokenId);
            // === NEW ===
            refundAmount += tokenPrices[tokenId];
            // ===========
        }

        // uint256 refundAmount = tokenIds.length * mintPrice;
        Address.sendValue(payable(msg.sender), refundAmount);
    }

    function refundGuaranteeActive() public view returns (bool) {
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

    // == NEW ==
    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        mintPrice = _mintPrice;
    }
    // ========

    function setRefundAddress(address _refundAddress) external onlyOwner {
        refundAddress = _refundAddress;
    }

    function setMerkleRoot(bytes32 _root) external onlyOwner {
        merkleRoot = _root;
    }

    function setBaseURI(string memory uri) external onlyOwner {
        baseURI = uri;
    }

    function toggleRefundCountdown() public onlyOwner {
        refundEndTime = block.timestamp + refundPeriod;
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