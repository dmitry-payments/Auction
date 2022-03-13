pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract Auction {
    // static
    IERC20 public token;
    IERC721 public erc721Instance;
    address public owner;
    uint public bidIncrement;
    uint public startBlock;
    uint public endBlock;
    uint public tokenID;
    uint32 public duration;

    // state
    enum states {NotStarted, Started, Canceled, End}
    states public auctionState = states.NotStarted;
    uint public highestBindingBid;
    address public highestBidder;
    mapping(address => uint256) public fundsByBidder;
    bool ownerHasWithdrawn;
    bool nftWasWithdrawn = false;

    event LogBid(address bidder, uint bid, address highestBidder, uint highestBid, uint highestBindingBid);
    event LogWithdrawal(address withdrawer, address withdrawalAccount, uint amount);
    event LogCanceled();

    modifier onlyOwner {
        require(msg.sender == owner, "Msg.sender is not owner");
        _;
    }

    modifier onlyNotOwner {
        require(msg.sender != owner, "Msg.sender is not owner");
        _;
    }

    modifier onlyAfterStart {
        require(auctionState == states.Started, "Auction state is Started");
        _;
    }

    modifier onlyBeforeEnd {
        require(auctionState != states.End, "Auction state is End");
        _;
    }

    modifier onlyNotCanceled {
        require(auctionState != states.Canceled, "Auction state is Canceled");
        _;
    }

    modifier onlyEndedOrCanceled {
        require(auctionState == states.End || auctionState == states.Canceled);
        _;
    }

    constructor (IERC20 _token) {
        token = _token;
    }

    function startAuction(uint _bidIncrement, uint32 _duration, uint256 _tokenID, address _tokenNFTAddress)  public {

        tokenID = _tokenID;
        erc721Instance = IERC721(_tokenNFTAddress);
        bidIncrement = _bidIncrement;
        duration = _duration;
    }

    function getHighestBid() public view returns (uint) {
        return fundsByBidder[highestBidder];//возвращает value самой крупной ставки
    }

    function placeBid (uint256 _amount) public
        onlyAfterStart
        onlyBeforeEnd
        onlyNotCanceled
        onlyNotOwner
        returns (bool success)
    {
        // reject payments of 0 ETH
        require(_amount != 0, "Auction: Amount == 0");
        require(token.allowance(msg.sender, address(this)) >= _amount, "Auction: amount is not enough");

        // calculate the user's total bid based on the current amount they've sent to the contract
        // plus whatever has been sent with this transaction 
        uint newBid = fundsByBidder[msg.sender] + _amount;

        // if the user isn't even willing to overbid the highest binding bid, there's nothing for us
        // to do except revert the transaction.
        require(newBid >= highestBindingBid, "Auction: newBid <= highestBindingBid");
        token.transferFrom(msg.sender, address(this), _amount);
        //highestBindingBid - последняя ставка сделанная по правилам с инкрементом

        // grab the previous highest bid (before updating fundsByBidder, in case msg.sender is the
        // highestBidder and is just increasing their maximum bid).
        uint highestBid = fundsByBidder[highestBidder]; //по дефолту ноль, так как переменная не появлялась ни разу

        fundsByBidder[msg.sender] = newBid;

        if (newBid <= highestBid) {
            // if the user has overbid the highestBindingBid but not the highestBid, we simply
            // increase the highestBindingBid and leave highestBidder alone.

            // note that this case is impossible if msg.sender == highestBidder because you can never
            // bid less ETH than you've already bid.

            highestBindingBid = min(newBid + bidIncrement, highestBid);
        } else {
            // if msg.sender is already the highest bidder, they must simply be wanting to raise
            // their maximum bid, in which case we shouldn't increase the highestBindingBid.

            // if the user is NOT highestBidder, and has overbid highestBid completely, we set them
            // as the new highestBidder and recalculate highestBindingBid.

            if (msg.sender != highestBidder) {
                highestBidder = msg.sender;
                highestBindingBid = min(newBid, highestBid + bidIncrement);
            }
            highestBid = newBid;
        }

        emit LogBid(msg.sender, newBid, highestBidder, highestBid, highestBindingBid);
        return true;
    }

    function min(uint a, uint b)
        private pure
        returns (uint)
    {
        if (a < b) return a;
        return b;
    }

    function cancelAuction() public
        onlyOwner
        onlyBeforeEnd
        onlyNotCanceled
        returns (bool success)
    {
        auctionState = states.Canceled;
        emit LogCanceled();
        return true;
    }

    function withdraw() public
        onlyEndedOrCanceled
        returns (bool success)
    {
        address withdrawalAccount;
        uint withdrawalAmount;

        if (auctionState == states.Canceled) {
            // if the auction was canceled, everyone should simply be allowed to withdraw their funds
            withdrawalAccount = msg.sender;
            withdrawalAmount = fundsByBidder[withdrawalAccount];
        } else {
            // the auction finished without being canceled

            if (msg.sender == owner) { //овнер нфт
                // а что бы изменилось если бы не было 3 стороны которая устраивает аукцион, овнер бы 
                //точно так же получал деньги по-моему, только был бы и овнером нфт и овнером аукциона
                // the auction's owner should be allowed to withdraw the highestBindingBid
                withdrawalAccount = msg.sender;
                withdrawalAmount = highestBindingBid;
                ownerHasWithdrawn = true;

            } else if (msg.sender == highestBidder) {
                // the highest bidder should only be allowed to withdraw the difference between their
                // highest bid and the highestBindingBid
                withdrawalAccount = highestBidder;
                if (ownerHasWithdrawn) {
                    withdrawalAmount = fundsByBidder[highestBidder];
                } else {
                    withdrawalAmount = fundsByBidder[highestBidder] - highestBindingBid;
                }
                if (!nftWasWithdrawn) {
                    erc721Instance.safeTransferFrom(address(this), msg.sender, tokenID);
                    nftWasWithdrawn == true;
                }

            } else {
                // anyone who participated but did not win the auction should be allowed to withdraw
                // the full amount of their funds
                withdrawalAccount = msg.sender;
                withdrawalAmount = fundsByBidder[withdrawalAccount];
            }
        }

        require(withdrawalAmount > 0, "WithdrawalAmount == 0");
        //if (withdrawalAmount == 0) throw;

        fundsByBidder[withdrawalAccount] -= withdrawalAmount;

        // send the funds
        token.transfer(withdrawalAccount, withdrawalAmount); //объект msg.sender вызывает функцию send от базового класса 
        //и отправляет сумму себе на счет? this.transfer(msg.sender) - почему не так? 

        emit LogWithdrawal(msg.sender, withdrawalAccount, withdrawalAmount);

        return true;
    }
}
