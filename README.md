# ERC721R

## About The Project

The goal of ERC721R is to add refund functionality to the ERC721 and ERC1155 standards. This repo contains community provided examples you can use in your own NFT smart contract.

## Motivation

The NFT space needs greater accountability. The space faces too many rugpulls and for the health of the NFT ecosystem as a whole we need better mechanisms to prevent these from happening.

Offering refunds provides greater protection for buyers and more legitimacy for creators.

The Azuki ERC721A provided gas improvements to the original ERC721 standard. ERC721R provides trustless refunds.

## How it works in practice

When you mint an NFT in an ERC721R collection the funds are held by the smart contract in escrow. The creators are unable to withdraw the funds till the waiting period has been completed. During this waiting period the buyer is able to return their NFT to the smart contract and receive their ETH back.

If the creators decide to rug, buyers will request their funds back before the waiting period has completed only losing gas costs for the transactions.

## Usage

Add the following code snippets to your smart contracts to add refunds:

```solidity
uint256 public constant refundPeriod = 45 days;
uint256 public refundEndTime;
address public refundAddress;

constructor() ERC721A("ERC721RExample", "ERC721R") {
    refundAddress = msg.sender;
    toggleRefundCountdown();
}

function isRefundGuaranteeActive() public view returns (bool) {
    return (block.timestamp <= refundEndTime);
}

function getRefundGuaranteeEndTime() public view returns (uint256) {
    return refundEndTime;
}

function refund(uint256[] calldata tokenIds) external {
    require(isRefundGuaranteeActive(), "Refund expired");

    for (uint256 i = 0; i < tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i];
        require(msg.sender == ownerOf(tokenId), "Not token owner");
        transferFrom(msg.sender, refundAddress, tokenId);
    }

    uint256 refundAmount = tokenIds.length * mintPrice;
    Address.sendValue(payable(msg.sender), refundAmount);
}

function toggleRefundCountdown() public onlyOwner {
    refundEndTime = block.timestamp + refundPeriod;
}

function setRefundAddress(address _refundAddress) external onlyOwner {
    refundAddress = _refundAddress;
}
```

## Benefits

For buyers:

- Low risk purchase (worst case scenario you get your money back minus gas costs)
- Protects against rug pulls
- Forces greater accountability from creators to deliver

For sellers:

- Builds trust with buyers

A benefit to both:

- The project floor price is unlikely to drop below the mint price while refunds are open.
- Short term flippers leave the project early leaving a high quality core intact.

Another thread on the benefits of refunds can be found in Daniel Tenner's Twitter thread:
https://twitter.com/swombat/status/1492484783036936192

## How long should the refund period be?

There's no one answer to this question, but some things to consider:

A longer refund period means:

- More time for the team to deliver before the refund period runs out.
- A longer delay till the team can access the funds.

What some other projects have done:

- Exodia offered a 14 day refund period.
- Curious Addy’s Trading Club offered a 100 day refund period.
- CryptoFighters is offering a 45 day refund period.

## Supporting ERC721R projects

We've created a list of high-quality buyers that have committed to purchase from the next 10 NFT projects to implement refunds. If you'd like to be added to the list you can fill in [this form](https://skilledcoil.typeform.com/erc721r).

As long as the project has a mint price of 0.2ETH or less with at least a 14-day trustless refund period, everyone in the list commits to mint. Of course, there's no guarantee minters won't execute a refund.

## Projects using ERC721R

- [CryptoFighters](https://cryptofighters.io) (for which ERC721R was built)
- [Exodia](https://exodia.io) - 14 day refund. Sold out
- [Curious Addys Trading Club](https://exodia.io) - 100 day refund. Sold out

## Roadmap

In the future we may see more complex implementations of ERC721R that include:

- Vesting over a period of time. For example, the creator is able to release 25% of the funds in the smart contract each month.
- Cliffs. For example, 10% of funds are immediately available for release, and the rest is released at a later date (allowing buyers to receive a 90% refund upon purchase). The benefit is that the creators have access to some of the funds raised while still mostly protecting buyers.

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".

Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

Distributed under the MIT License. See `LICENSE.txt` for more information.

## Disclaimer

**Exodia Labs is not liable for any outcomes as a result of using ERC721R.** DYOR.

## Contact

- elie222 (owner) - [@elie2222](https://twitter.com/elie2222)
