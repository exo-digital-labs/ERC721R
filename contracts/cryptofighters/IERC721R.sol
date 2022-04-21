// SPDX-License-Identifier: MIT
// Creator: Exo Digital Labs

pragma solidity ^0.8.4;

interface IERC721R {
  function refund(uint256[] calldata tokenIds) external;

  function getRefundPrice(uint256 tokenId) external view returns (uint256);

  function getRefundGuaranteeEndTime() external view returns (uint256);

  function isRefundGuaranteeActive() external view returns (bool);
}
