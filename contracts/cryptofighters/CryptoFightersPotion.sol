// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract CryptoFightersPotion is ERC1155, Ownable {
    using Strings for uint256;

    address public cryptoFightersAlliance; // Address of crypto fighters alliance contract
    address public cryptoFightersV1; // Address of V1 fighter contract
    bytes32 public merkleRoot; // Merkle root for claiming potions
    string private baseURI; // Base uri for potions

    uint256 public constant TYPE_ID = 0; // There is only one potion type

    mapping(address => bool) public hasClaimedPotions; // mapping account => has claimed potion

    /**
     * @dev triggered after owner sets base uri
     */
    event SetBaseURI(string indexed _baseURI);

    /**
     * @dev Constructor used to set state variables
     */
    constructor(string memory _baseURI, address _cryptoFightersV1)
        ERC1155(_baseURI)
    {
        baseURI = _baseURI;
        cryptoFightersV1 = _cryptoFightersV1;
        emit SetBaseURI(baseURI);
    }

    /**
     * @dev Allows owner to set Crypto Fighters Alliance address
     */
    function setCryptoFightersAllianceContract(address _cryptoFightersAlliance) external onlyOwner {
        cryptoFightersAlliance = _cryptoFightersAlliance;
    }

    /**
     * @dev Allows caller to claim potions
     *
     * Requirements:
     *
     * - Must provide valid merkle proof
     * - Must not have already claimed
     */
    function claimPotions(uint256 _amount, bytes32[] calldata _proof) external {
        require(
            _canClaimAmount(msg.sender, _amount, _proof, merkleRoot),
            "Invalid proof submitted"
        );
        require(!hasClaimedPotions[msg.sender], "Already claimed potions");
        hasClaimedPotions[msg.sender] = true;
        _mint(msg.sender, TYPE_ID, _amount, "");
    }

    /**
     * @dev Allows caller to claim potions
     *
     * Requirements:
     *
     * - Must provide valid merkle proof
     * - Must not have already claimed
     */
    function burnPotionForAddress(address burnTokenAddress, uint256 amount)
        external
    {
        require(msg.sender == cryptoFightersAlliance, "Invalid burner address");
        _burn(burnTokenAddress, TYPE_ID, amount);
    }

    /**
     * @dev Sets merkle root for claiming potions
     */
    function setMerkleRoot(bytes32 _root) external onlyOwner {
        merkleRoot = _root;
    }

    /**
     * @dev Returns keccak256 hash of encoded address and amount
     */
    function _leaf(address _account, uint256 _amount)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_account, _amount));
    }

    /**
     * @dev Returns true if valid proof is provided for _account, _amount belonging in merkle tree `_root`
     */
    function _canClaimAmount(
        address _account,
        uint256 _amount,
        bytes32[] calldata _proof,
        bytes32 _root
    ) internal pure returns (bool) {
        return MerkleProof.verify(_proof, _root, _leaf(_account, _amount));
    }

    /**
     * @dev Sets base uri
     */
    function updateBaseUri(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
        emit SetBaseURI(baseURI);
    }

    /**
     * @dev Returns uri of provided type id
     */
    function uri(uint256 typeId) public view override returns (string memory) {
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, typeId.toString()))
                : baseURI;
    }
}
