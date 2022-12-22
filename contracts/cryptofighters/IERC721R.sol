// SPDX-License-Identifier: MIT
// Creator: Exo Digital Labs

pragma solidity ^0.8.4;


/*
 * WARNING: This uses the old version of the ERC721R interface. The new version can be found in contracts/IERC721R.sol, or at the following link:
 * https://eips.ethereum.org/EIPS/eip-5507
 */
interface IERC721R {
    event Refund(
        address indexed _sender,
        uint256 indexed _tokenId,
        uint256 _amount
    );

    function refund(uint256[] calldata tokenIds) external;

    function getRefundPrice(uint256 tokenId) external view returns (uint256);

    function getRefundGuaranteeEndTime() external view returns (uint256);

    function isRefundGuaranteeActive() external view returns (bool);
}
