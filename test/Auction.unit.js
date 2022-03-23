const { advanceBlockAndSetTime } = require('./helpers/standingTheTime');
const { expect, assert } = require('chai'); //expect - проверка
const { expectRevert, expectEvent, BN } = require('@openzeppelin/test-helpers'); // expectRevert - ожидание того что транзакция будет отклонена, expectEvent - ожидание эвента
const { web3 } = require('@openzeppelin/test-helpers/src/setup'); //web3 - blockchain
const { MAX_UINT256 } = require('@openzeppelin/test-helpers/src/constants');
//const { artifacts } = require('hardhat');


const ERC20Token = artifacts.require("ERC20"); //здесь мы сделали инстанс. артифакты - то куда комплируются файлы. это бинарники в котором sol скомпилирован в байт код для evm.
const ERC721Token = artifacts.require("ERC721");
const Auction = artifacts.require("Auction");
const zeroAddress = "0x0000000000000000000000000000000000000000";

contract('Auction', function (accounts) { 
    const [owner, account1, account2] = accounts;

    before(async function () { 
        this.token = await ERC20Token.new("DESU", "DESU", {from: owner});
        this.token.transfer(account1, 1000);
        this.token.transfer(account2, 1000);
        this.auction = await Auction.new(this.token.address, { from: owner });
        this.nft = await ERC721Token.new("NFT", "NFT", {from: owner});
        await this.nft.safeTransferFrom(owner, this.auction.address, 666);
    });

    describe('method: startAuction', async function () {
        it('positive', async function () {
            await this.auction.startAuction(1, 11, 666, this.nft.address, { from: owner });
            expect(await this.auction.bidIncrement()).to.bignumber.equals(new BN(1));
            expect(await this.auction.duration()).to.bignumber.equals(new BN(11));
            expect(await this.auction.tokenID()).to.bignumber.equals(new BN(666));
            expect(this.nft.address).equal(await this.auction.erc721Instance());
        });

        it('negative', async function () {
            await expectRevert(this.auction.startAuction(1, 11, 666, zeroAddress, { from: owner }), "Address can't be 0");
        });
    });

    describe('method: placeBid', async function () {
        it('positive', async function () {
            await this.token.approve(this.auction.address, 666, { from: account1 });
            const receipt = await (this.auction.placeBid(1, { from: account1 }));
            await expectEvent(receipt, "LogBid", {
                bidder: account1,
                bid: await this.auction.fundsByBidder(account1),
                highestBidder: account1,
                highestBid: "1",
                highestBindingBid: "1",
            });
        });

        it('negative', async function () {
            await expectRevert(this.auction.placeBid(0, { from: account1 }),
                "Auction: Amount == 0");
                await expectRevert(this.auction.placeBid(666, { from: account1 }),
                "Auction: amount is not enough");  
        });
    });

    describe('method: withdraw', async function () {
        it('negative', async function () { 
            await expectRevert(this.auction.withdraw({ from: account2 }), "incorrect auction state");    
        });
        it('positive', async function () {
            await this.auction.cancelAuction({from: owner});
            const receipt = await (this.auction.withdraw({ from: account1 }));
            await expectEvent(receipt, "LogWithdrawal", {
                withdrawer: account1,
                withdrawalAccount: account1,
                amount: "1",
            });
        });
    });
});
