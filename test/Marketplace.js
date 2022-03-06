const { expect } = require("chai");

describe("Marketplace contract", async function () {
  let erc20DemoToken;
  let marketplace;
  let marketplaceNFT;
  let marketplaceOwner;
  let creator;
  let buyer;
  let users;
  let nfts;

  beforeEach(async function () {
    [marketplaceOwner, creator, buyer, ...users] = await ethers.getSigners();

    const demoToken = await ethers.getContractFactory("DemoERC20");
    erc20DemoToken = await demoToken.deploy();

    // deploy the marketplace token
    const marketplaceToken = await ethers.getContractFactory("Marketplace");
    marketplace = await marketplaceToken.deploy(erc20DemoToken.address);

    // deploy the MarketplaceNFT Token
    const marketplaceNftToken = await ethers.getContractFactory("MarketplaceNFT");
    marketplaceNFT = await marketplaceNftToken.deploy(marketplace.address);

    // mint some NFTs using the creator wallet
    const nftOne = await marketplaceNFT.connect(creator).createToken("uriOne");
    const nftTwo = await marketplaceNFT.connect(creator).createToken("uriTwo");
    const nftThree = await marketplaceNFT.connect(creator).createToken("uriThree");
    nfts = [nftOne, nftTwo, nftThree];
  });

  describe("Marketplace - listing items", async function () {
    it("Should be able to list an item and emit an event with it's data", async function () {
      const listTransaction = await marketplace
        .connect(creator)
        .listItem(marketplaceNFT.address, 1, 10, 20);

      const transactionRecipt = await listTransaction.wait();
      const newItemId = transactionRecipt.events[0].args.itemId;
      const listedItem = await marketplace.idToMarketplaceItem(newItemId);

      expect(listedItem.itemId).to.equal(newItemId);
      expect(listedItem.asset.contractAddress).to.equal(marketplaceNFT.address);
      expect(listedItem.asset.tokenId).to.equal(1);
      expect(listedItem.asset.owner).to.equal(creator.address);
      expect(listedItem.minPrice).to.equal(10);
      expect(listedItem.buyNowPrice).to.equal(20);
    });
  });

  it("Should not allow to list an item that the user doesn't own or have permission to trade", async function () {
    await expect(
      marketplace.connect(buyer).listItem(marketplaceNFT.address, 1, 10, 20)
    ).to.be.revertedWith("You must be the owner or approved of the asset to be able to list it");
  });

  describe("Marketplace - Buy now", async function () {
    let listedItem;
    beforeEach(async function () {
      const listTransaction = await marketplace
        .connect(creator)
        .listItem(marketplaceNFT.address, 1, 10, 20);

      const transactionRecipt = await listTransaction.wait();
      const newItemId = transactionRecipt.events[0].args.itemId;
      listedItem = await marketplace.idToMarketplaceItem(newItemId);
    });

    it("Should allow to change the buy now price of an item", async function () {
      await marketplace.connect(creator).setBuyNowPrice(listedItem.itemId, 10);

      itemWithNewPrice = await marketplace.idToMarketplaceItem(listedItem.itemId);

      expect(itemWithNewPrice.buyNowPrice).to.equal(10);
    });

    it("Should not allow anyone besides the item owner to change the price of an item", async function () {
      await expect(
        marketplace.connect(buyer).setBuyNowPrice(listedItem.itemId, 10)
      ).to.be.revertedWith("You are not the owner of the item");
    });

    it("Should be able to buy an item and emit an event with it's data", async function () {
      const buyTransaction = await marketplace
        .connect(buyer)
        .buyItem(listedItem.itemId, { value: 20 });

      const transactionRecipt = await buyTransaction.wait();
      const emittedEvent = transactionRecipt.events[2].args;

      expect(emittedEvent.itemId).to.equal(listedItem.itemId);
      expect(emittedEvent.nftContract).to.equal(marketplaceNFT.address);
      expect(emittedEvent.tokenId).to.equal(1);
      expect(emittedEvent.seller).to.equal(creator.address);
      expect(emittedEvent.seller).to.equal(creator.address);
      expect(emittedEvent.price).to.equal(20);
    });

    it("should not allow to buy an item with less or more ether than the buy now price", async function () {
      await expect(
        marketplace.connect(buyer).buyItem(listedItem.itemId, { value: 10 })
      ).to.be.revertedWith("The money submitted is not equal to the buy now price");

      await expect(
        marketplace.connect(buyer).buyItem(listedItem.itemId, { value: 30 })
      ).to.be.revertedWith("The money submitted is not equal to the buy now price");
    });

    it("Should not allot to buy an item that its buy now option is disabled", async function () {
      await marketplace.connect(creator).setBuyNowPrice(listedItem.itemId, 0);

      await expect(
        marketplace.connect(buyer).buyItem(listedItem.itemId, { value: 20 })
      ).to.be.revertedWith("This item doesn't support the buy now option");
    });

    it("Should give the platform thr right cut of a sale", async function () {
      await marketplace.setMarketplaceCut(15);

      await expect(() =>
        marketplace.connect(buyer).buyItem(listedItem.itemId, { value: 20 })
      ).to.changeBalance(marketplace, 3);
    });

    it("Should give the creator thr right cut of a sale", async function () {
      await marketplace.setMarketplaceCut(15);

      await expect(() =>
        marketplace.connect(buyer).buyItem(listedItem.itemId, { value: 20 })
      ).to.changeEtherBalance(creator, 17);
    });

    it("Should take the right amount of money from the buyer", async function () {
      await expect(() =>
        marketplace.connect(buyer).buyItem(listedItem.itemId, { value: 20 })
      ).to.changeEtherBalance(buyer, -20);
    });
  });

  describe("Marketplace - Bidding", async function () {
    let listedItem;
    beforeEach(async function () {
      const listTransaction = await marketplace
        .connect(creator)
        .listItem(marketplaceNFT.address, 1, 10, 20);

      const transactionRecipt = await listTransaction.wait();
      const newItemId = transactionRecipt.events[0].args.itemId;
      listedItem = await marketplace.idToMarketplaceItem(newItemId);

      await erc20DemoToken.mint(buyer.address, 1000);
    });

    it("Should nto allow bidding under the minimum price of an item", async function () {
      await expect(marketplace.connect(buyer).submitBid(listedItem.itemId, 5)).to.be.revertedWith(
        "Bid value must be equal or higher than the minimum price of the item"
      );
    });

    it("Should not allow bidding for someone who didn't approve the marketplace for the bid amount", async function () {
      await expect(marketplace.connect(buyer).submitBid(listedItem.itemId, 15)).to.be.revertedWith(
        "You don't have enough money or didn't give us permissions for that amount"
      );
    });

    it("Should not allow bidding for someone who approved the marketplace for the bid amount but don't have enough money", async function () {
      await erc20DemoToken.connect(users[0]).approve(marketplace.address, 15);

      await expect(
        marketplace.connect(users[0]).submitBid(listedItem.itemId, 15)
      ).to.be.revertedWith(
        "You don't have enough money or didn't give us permissions for that amount"
      );
    });

    it("Should allow to post a bid after giving approval and having enough money", async function () {
      await erc20DemoToken.connect(buyer).approve(marketplace.address, 15);

      await marketplace.connect(buyer).submitBid(listedItem.itemId, 15);

      const openBids = await marketplace.getAllOpenBidsForItem(listedItem.itemId);
      expect(openBids.length).to.be.equal(1);
      expect(openBids[0].bidder).to.be.equal(buyer.address);
      expect(openBids[0].price).to.be.equal(15);
    });

    it("Should not allow anyone to accept a bid if he is not the creator of the item", async function () {
      await erc20DemoToken.connect(buyer).approve(marketplace.address, 15);

      await marketplace.connect(buyer).submitBid(listedItem.itemId, 15);

      await expect(
        marketplace.connect(buyer).acceptBid(listedItem.itemId, buyer.address, 15)
      ).to.be.revertedWith("You are not the owner of the item");
    });

    it("Should allow the creator to accept a bid and creator recive the right amount of money", async function () {
      await erc20DemoToken.connect(buyer).approve(marketplace.address, 15);

      await marketplace.connect(buyer).submitBid(listedItem.itemId, 15);

      await marketplace.connect(creator).acceptBid(listedItem.itemId, buyer.address, 15);

      const creatorBalance = await erc20DemoToken.balanceOf(creator.address);
      expect(creatorBalance).to.equal(15);
    });

    it("Should change ownership of the asset after succesfully acecepting a bid", async function () {
      await erc20DemoToken.connect(buyer).approve(marketplace.address, 15);

      await marketplace.connect(buyer).submitBid(listedItem.itemId, 15);

      await marketplace.connect(creator).acceptBid(listedItem.itemId, buyer.address, 15);

      await expect(await marketplaceNFT.ownerOf(listedItem.asset.tokenId)).to.equal(buyer.address);
    });

    it("Should remove the bid after a bid is accepted", async function () {
      await erc20DemoToken.connect(buyer).approve(marketplace.address, 15);

      await marketplace.connect(buyer).submitBid(listedItem.itemId, 15);

      await marketplace.connect(creator).acceptBid(listedItem.itemId, buyer.address, 15);

      const openBids = await marketplace.getAllOpenBidsForItem(listedItem.itemId);
      expect(openBids.length).to.equal(0);
    });
  });
});
