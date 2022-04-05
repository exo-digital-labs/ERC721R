// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract CryptoFightersPotion is ERC1155, Ownable {
    using Strings for uint256;

    address public cryptoFightersV2;
    address public cryptoFightersV1;
    bytes32 public merkleRoot;
    string private baseURI;

    uint256 public constant TYPE_ID = 0;

    // mapping account => has claimed potion
    mapping(address => bool) public hasClaimedPotions;

    event SetBaseURI(string indexed _baseURI);

    constructor(string memory _baseURI, address _cryptoFightersV1)
        ERC1155(_baseURI)
    {
        baseURI = _baseURI;
        cryptoFightersV1 = _cryptoFightersV1;
        emit SetBaseURI(baseURI);
    }

    function setV2Contract(address _cryptoFightersV2) external onlyOwner {
        cryptoFightersV2 = _cryptoFightersV2;
    }

    function claimPotions(uint256 _amount, bytes32[] calldata _proof) external {
        require(
            _canClaimAmount(msg.sender, _amount, _proof, merkleRoot),
            "Invalid proof submitted"
        );
        require(!hasClaimedPotions[msg.sender], "Already claimed potions");
        hasClaimedPotions[msg.sender] = true;
        _mint(msg.sender, TYPE_ID, _amount, "");
    }

    function burnPotionForAddress(address burnTokenAddress, uint256 amount)
        external
    {
        require(msg.sender == cryptoFightersV2, "Invalid burner address");
        _burn(burnTokenAddress, TYPE_ID, amount);
    }

    function setMerkleRoot(bytes32 _root) external onlyOwner {
        merkleRoot = _root;
    }

    function _leaf(address _account, uint256 _amount)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_account, _amount));
    }

    function _canClaimAmount(
        address _account,
        uint256 _amount,
        bytes32[] calldata _proof,
        bytes32 _root
    ) internal pure returns (bool) {
        return MerkleProof.verify(_proof, _root, _leaf(_account, _amount));
    }

    function updateBaseUri(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
        emit SetBaseURI(baseURI);
    }

    function uri(uint256 typeId) public view override returns (string memory) {
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, typeId.toString()))
                : baseURI;
    }
}
