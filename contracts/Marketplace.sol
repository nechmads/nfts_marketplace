// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract Marketplace is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    address immutable ACCEPTED_CURRENCY_ADDRESS;
    IERC20 immutable currencyToken;

    // The address of the marketplace bank where cut of sales will be sent to
    address internal marketPlaceBankAddress;

    // The cut in percantage the marketplace takes from every initial sale of an item
    uint8 internal marketplaceCut;

    // Counter for all marketplace items ids
    Counters.Counter internal _itemIds;

    // Mark that the marketplace is willing to accept just NFTs from a specific contract
    address internal allowedNftContract;

    // Allows to check if a specific nft is already listed on the marketplace based on its contract address and token id
    mapping(address => mapping(uint256 => bool)) internal _nftsOnMarketplace;

    // Represent any asset in the marketplace
    struct Asset {
        address owner;
        address contractAddress;
        uint256 tokenId;
    }

    struct Bid {
        address bidder;
        uint256 price;
    }

    // Represent an asset that was listed on the marketplace
    struct MarketplaceItem {
        uint256 itemId;
        Asset asset;
        uint256 minPrice;
        uint256 buyNowPrice;
        bool isLive;
        bool isSold;
    }

    // Get any item that is listed on the marketplace by its marketplace item id
    mapping(uint256 => MarketplaceItem) public idToMarketplaceItem;

    // Non time based bids. itemId => list of bids
    mapping(uint256 => Bid[]) public openBids;

    event ItemListed(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 buyNowPrice,
        uint256 minPrice
    );

    event ItemSold(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price
    );

    event BidSubmitted(uint256 indexed itemId, address bidder, uint256 price);

    event BidCancelled(uint256 indexed itemId, address bidder, uint256 price);

    event BidAccepted(uint256 indexed itemId, address bidder, uint256 price);

    /*
    Only the item owner can call functions using this modifier
    */
    modifier onlyItemOwner(uint256 itemid) {
        require(
            msg.sender == idToMarketplaceItem[itemid].asset.owner,
            "You are not the owner of the item"
        );
        _;
    }

    /*
    Makes sure the item sent to the method using this modfier does exist in the marketplace
    */
    modifier itemExist(uint256 itemId) {
        require(itemId <= _itemIds.current(), "Item doesn't exist");
        _;
    }

    /*
    Makes sure the item sent to the method using this modifier wasn't sold already and is sale status is live
    */
    modifier itemOnSale(uint256 itemId) {
        MarketplaceItem storage item = idToMarketplaceItem[itemId];
        require(item.isLive == true, "Item sale status is not live");
        require(item.isSold == false, "Item already sold");
        _;
    }

    constructor(address approvedCurrencyAddres, address bankAddress) {
        ACCEPTED_CURRENCY_ADDRESS = approvedCurrencyAddres;
        currencyToken = IERC20(approvedCurrencyAddres);
        marketPlaceBankAddress = bankAddress;
    }

    receive() external payable {}

    /*
    Set the address of the marketplace bank. Marketplace cut of sales will be sent to this address.
    */
    function setMarketplaceBank(address bankAddress) public onlyOwner {
        require(
            bankAddress != address(0),
            "Bank address can't be address zero"
        );
        marketPlaceBankAddress = bankAddress;
    }

    /*
    Returns the address of the marketplace bank
    */
    function getMarketplaceBankAddress() public view returns (address) {
        return marketPlaceBankAddress;
    }

    // This function set the marketplace to accept only NFTs of a specified contract. Only owners can call this function.
    function setMarketplaceToAcceptOnlyContract(address contractToAccept)
        public
        onlyOwner
    {
        allowedNftContract = contractToAccept;
    }

    // This function set the marketplace to accept NFTs of all contracts. Only owners can call this function.
    function setMarketplaceToAcceptAllContracts() public onlyOwner {
        allowedNftContract = address(0);
    }

    /*
    Set the cut the marketplace takes from every initial sale
    */
    function setMarketplaceCut(uint8 cut) public onlyOwner {
        require(
            cut >= 0 && cut <= 100,
            "Cut percantage must be between 0 to 100"
        );

        marketplaceCut = cut;
    }

    /*
    Calculate what is the amount of money the marketpalce takes from a sale
    */
    function calculateMarketplaceCut(uint256 salePrice, uint8 cut)
        internal
        pure
        returns (uint256)
    {
        return (salePrice * cut) / 100;
    }

    /*
    List a new NFT on the marketplace
    */
    function listItem(
        address assetContract,
        uint256 tokenId,
        uint256 minPrice,
        uint256 buyNowPrice
    ) public nonReentrant returns (uint256 newItemId) {
        // Check to see if the NFT is already listed on the marketplace
        require(
            _nftsOnMarketplace[assetContract][tokenId] == false,
            "NFT is already listed on the marketplace"
        );

        // Check to see if the marketplace is accepting the NFT contract
        require(
            isAcceptinfNftsOfContract(assetContract),
            "You can't list NFTs of this contract at the moment"
        );

        // Check to see if the caller is the owner of the asset or approved to transfer it
        address tokenOwner = IERC721(assetContract).ownerOf(tokenId);
        require(
            msg.sender == IERC721(assetContract).getApproved(tokenId) ||
                msg.sender == tokenOwner,
            "You must be the owner or approved of the asset to be able to list it"
        );

        // TODO: If we want to deal with NFTs not minted by us, we need to ask for approval permissions on the token

        // Add the asset to the marketplace
        newItemId = addAssetToMarketplace(
            assetContract,
            tokenId,
            minPrice,
            buyNowPrice
        );

        // Emit event to the blockchain
        emit ItemListed(
            newItemId,
            assetContract,
            tokenId,
            msg.sender,
            buyNowPrice,
            minPrice
        );

        return newItemId;
    }

    /*
    Set the buy now price for an item. Set to 0 to disable the buy now option. Only the item owner can call this function
    */
    function setBuyNowPrice(uint256 itemId, uint256 newPrice)
        public
        onlyItemOwner(itemId)
    {
        idToMarketplaceItem[itemId].buyNowPrice = newPrice;
    }

    function buyItem(uint256 itemId)
        public
        payable
        nonReentrant
        itemExist(itemId)
    {
        MarketplaceItem storage item = idToMarketplaceItem[itemId];
        require(item.isSold == false, "Item already sold");
        require(
            item.buyNowPrice != 0,
            "This item doesn't support the buy now option"
        );
        require(
            msg.value == item.buyNowPrice,
            "The money submitted is not equal to the buy now price"
        );

        _handlePayments(item.asset.owner, item.buyNowPrice);

        // Transfer the actual NFT to the buyer
        IERC721(item.asset.contractAddress).safeTransferFrom(
            item.asset.owner,
            msg.sender,
            item.asset.tokenId
        );

        emit ItemSold(
            itemId,
            item.asset.contractAddress,
            item.asset.tokenId,
            item.asset.owner,
            msg.sender,
            item.buyNowPrice
        );

        item.asset.owner = msg.sender;
        item.buyNowPrice = 0;
        item.isSold = true;
    }

    /*
    Post a bid on one of the items in the marketplace
    Note that the user must first approve the marketplace contract to spend at minimum the amount of the bid
    */
    function submitBid(uint256 itemId, uint256 bid)
        public
        itemOnSale(itemId)
        returns (bool)
    {
        //TODO: Decide if we want to allow multiple bids on the same item from the same bidder

        MarketplaceItem storage item = idToMarketplaceItem[itemId];

        // Check the bid is above the minimum price of the item
        require(
            bid >= item.minPrice,
            "Bid value must be equal or higher than the minimum price of the item"
        );

        // Check to see that the bidder holds enough money and gave us (the contract) permission to withdraw it if the bid will be accepted.
        require(
            doesHaveRequiredBalanceAndAllowance(msg.sender, bid),
            "You don't have enough money or didn't give us permissions for that amount"
        );

        // Add the bid
        openBids[itemId].push(Bid({bidder: msg.sender, price: bid}));

        emit BidSubmitted(itemId, msg.sender, bid);

        return true;
    }

    /*
    Cancel a bid for an item
    */
    function cancelBid(uint256 itemId, uint256 price) public {
        Bid[] storage allBids = openBids[itemId];

        for (uint256 index; index < allBids.length; index++) {
            Bid storage currentBid = allBids[index];
            if (currentBid.bidder == msg.sender && currentBid.price == price) {
                allBids[index] = allBids[allBids.length - 1];
                allBids.pop();

                emit BidCancelled(itemId, msg.sender, price);
                break;
            }
        }
    }

    /*
    Returns all the open bids for a specified item
    */
    function getAllOpenBidsForItem(uint256 itemId)
        public
        view
        returns (Bid[] memory allOpenBids)
    {
        Bid[] storage itemBids = openBids[itemId];

        allOpenBids = new Bid[](openBids[itemId].length);
        for (uint256 index = 0; index < itemBids.length; index++) {
            allOpenBids[index] = itemBids[index];
        }
    }

    /*
    Accept a bid. This method can be called just by the owner of the item we want to accept the bid for
    */
    function acceptBid(
        uint256 itemId,
        address bidder,
        uint256 price
    ) public onlyItemOwner(itemId) {
        Bid[] storage allBids = openBids[itemId];

        for (uint256 index; index < allBids.length; index++) {
            Bid storage currentBid = allBids[index];
            if (currentBid.bidder == bidder && currentBid.price == price) {
                MarketplaceItem storage itemSold = idToMarketplaceItem[itemId];

                // Calculate how much the marketplace takes and how much we need to transfer to the seller
                uint256 platformCut = calculateMarketplaceCut(
                    currentBid.price,
                    marketplaceCut
                );

                uint256 sellerCut = price - platformCut;

                // Try to transfer the bid amount to the onwer of the asset
                bool isTransferSuccessful = currencyToken.transferFrom(
                    payable(currentBid.bidder),
                    msg.sender,
                    sellerCut
                );

                if (isTransferSuccessful) {
                    // Transfer the platform cut of the sale
                    if (platformCut > 0) {
                        currencyToken.transferFrom(
                            payable(currentBid.bidder),
                            marketPlaceBankAddress,
                            platformCut
                        );
                    }

                    // Transfer the NFT to the bidder
                    IERC721(itemSold.asset.contractAddress).safeTransferFrom(
                        itemSold.asset.owner,
                        currentBid.bidder,
                        itemSold.asset.tokenId
                    );

                    emit BidAccepted(itemId, currentBid.bidder, price);

                    allBids[index] = allBids[allBids.length - 1];
                    allBids.pop();

                    break;
                }
            }
        }
    }

    /*
    Private function to add an asset to the marketplace
    */
    function addAssetToMarketplace(
        address assetContract,
        uint256 tokenId,
        uint256 minPrice,
        uint256 buyNowPrice
    ) private returns (uint256 newItemId) {
        _itemIds.increment();
        newItemId = _itemIds.current();

        // Create the new asset
        Asset memory newAsset = Asset({
            owner: payable(msg.sender),
            contractAddress: assetContract,
            tokenId: tokenId
        });

        // Add the asset to the marketplace and setting it's sale status to live
        idToMarketplaceItem[newItemId] = MarketplaceItem({
            itemId: newItemId,
            asset: newAsset,
            minPrice: minPrice,
            buyNowPrice: buyNowPrice,
            isLive: true,
            isSold: false
        });
        _nftsOnMarketplace[assetContract][tokenId] = true;

        return newItemId;
    }

    /*
    Check to see if the marketplace accepts nfts of a specified contract
    */
    function isAcceptinfNftsOfContract(address nftContract)
        internal
        view
        returns (bool)
    {
        return (allowedNftContract == address(0) ||
            allowedNftContract == nftContract);
    }

    /*
    Check if a certain address has the requried balance and gave us the approval of using it
    */
    function doesHaveRequiredBalanceAndAllowance(
        address addressToCheck,
        uint256 amount
    ) internal view returns (bool) {
        return (currencyToken.balanceOf(addressToCheck) >= amount &&
            currencyToken.allowance(addressToCheck, address(this)) >= amount);
    }

    /*
    Handle the payments after a sell of an iterm. Transfer the right amount of money to the creator and handles also the cut to the platform
    */
    function _handlePayments(address creator, uint256 price) internal virtual {
        // Calculate how much the marketplace takes and how much we need to transfer to the seller
        uint256 platformCut = calculateMarketplaceCut(price, marketplaceCut);

        uint256 sellerCut = price - platformCut;

        // Transfer the money to the owner of the asset
        if (sellerCut > 0) {
            payable(creator).transfer(sellerCut);
        }

        // Transfer the platform cut to the marketplace contract
        if (platformCut > 0) {
            payable(marketPlaceBankAddress).transfer(platformCut);
        }
    }
}
