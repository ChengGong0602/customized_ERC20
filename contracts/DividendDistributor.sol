
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Address.sol";
import "./IDividendDistributor.sol";
import "./IChengRouter.sol";
import "./IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DividendDistributor is IDividendDistributor {
    using Address for address payable;   

    address _token;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    IERC20 REWARD = IERC20(0xc778417E063141139Fce010982780140Aa0cD5Ab);
    address WETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab; 
    
    IChengRouter router;

    address public constant marketingWallet = address(0x7488D2d66BdaEf675FBcCc5266d44C6EB313a97b);
    
    address[] shareholders;
    mapping (address => uint256) shareholderIndexes;
    mapping (address => uint256) shareholderClaims;

    mapping (address => Share) public shares;

    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareAccuracyFactor = 10 ** 36;

    uint256 public minPeriod = 60 minutes;
    uint256 public minDistribution = 10 * (10 ** 18);

    uint256 public marketingShare = 28;

    uint256 currentIndex;

    bool initialized;
    modifier initialization() {
        require(!initialized);
        _;
        initialized = true;
    }

    modifier onlyToken() {
        require(msg.sender == _token); _;
    }

    constructor (address _router) {
        router = _router != address(0)
            ? IChengRouter(_router)
            : IChengRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _token = msg.sender;
    }


    function setFeeShares(uint256 _marketingShare) external onlyToken {
        marketingShare = _marketingShare;
    }

    function setShare(address shareholder, uint256 amount) external override onlyToken {
        if(shares[shareholder].amount > 0){
            distributeDividend(shareholder);
        }

        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        } else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }

        totalShares = totalShares- (shares[shareholder].amount) + (amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }

    function deposit() external payable override onlyToken {
        uint256 _available = msg.value;

        uint256 marketingAllocation = _available/(100)*(marketingShare); 

        payable(marketingWallet).sendValue(marketingAllocation);

        uint256 _totalAvailable = address(this).balance;

        uint256 balanceBefore = REWARD.balanceOf(address(this));

        IWETH(WETH).deposit{value: _totalAvailable}();

        uint256 amount = REWARD.balanceOf(address(this)) - (balanceBefore);

        totalDividends = totalDividends+ (amount);
        dividendsPerShare = dividendsPerShare + (dividendsPerShareAccuracyFactor*(amount)/(totalShares));
        
    }

    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;

        if(shareholderCount == 0) { return; }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        uint256 iterations = 0;

        while(gasUsed < gas && iterations < shareholderCount) {
            if(currentIndex >= shareholderCount){
                currentIndex = 0;
            }

            if(shouldDistribute(shareholders[currentIndex])){
                distributeDividend(shareholders[currentIndex]);
            }

            gasUsed = gasUsed+(gasLeft-(gasleft()));
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }

    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
                && getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) internal {
        if(shares[shareholder].amount == 0){ return; }

        uint256 amount = getUnpaidEarnings(shareholder);
        if(amount > 0){
            totalDistributed = totalDistributed+(amount);
            REWARD.transfer(shareholder, amount);
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised = shares[shareholder].totalRealised+(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        }
    }

    function claimDividend() external {
        distributeDividend(msg.sender);
    }

    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends-(shareholderTotalExcluded);
    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share*(dividendsPerShare)/(dividendsPerShareAccuracyFactor);
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder];
        shareholders.pop();
    }
}