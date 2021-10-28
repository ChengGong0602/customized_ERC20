// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Address.sol";
import "./IChengFactory.sol";
import "./IChengRouter.sol";
import "./DividendDistributor.sol";



contract ChengToken is IERC20, Ownable {
    using Address for address;

    address REWARD = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address WETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab; 
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
    address MARKETING = 0x7488D2d66BdaEf675FBcCc5266d44C6EB313a97b; 

    string constant _name = "ChengToken";
    string constant _symbol = "CTN";
    uint8 constant _decimals = 18;

    uint256 _totalSupply = 200000000 * (10 ** _decimals); // 200 M
    uint256 public _maxTxAmount = ( _totalSupply * 1 ) / 100;
    uint256 public _maxWalletToken = ( _totalSupply * 5 ) / 100;

    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => bool) isDividendExempt;

    uint256 liquidityFee    = 5;
    uint256 burnFee   = 5;
    uint256 marketingFee    = 10;

    uint256 public totalFee = 20;
    uint256 feeDenominator  = 1000;

    address public autoLiquidityReceiver;
    address public marketingFeeReceiver; 

    uint256 targetLiquidity = 25;
    uint256 targetLiquidityDenominator = 100;

    IChengRouter public router;
    address public pair;

    uint256 public launchedAt;



    DividendDistributor public distributor;
    uint256 distributorGas = 300000;
    
    uint256 public swapThreshold = (getCirculatingSupply() * 50 ) / 10000000;
    uint256 public tradeSwapVolume = (getCirculatingSupply() * 100 ) / 10000000;
    bool inSwap;

    bool public tradingEnabled = false; //once enabled its final and cannot be changed

    uint256 minimumTokenBalanceForDividends = 200000 * (10 ** _decimals); //must hold 200000+ tokens to receive shareholding in dividends

    modifier swapping() { inSwap = true; _; inSwap = false; }

    constructor () {
        router = IChengRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); //uniswap
        pair = IChengFactory(router.factory()).createPair(WETH, address(this));
        _allowances[address(this)][address(router)] = uint256(0);

        distributor = new DividendDistributor(address(router));

        isFeeExempt[msg.sender] = true;
        isTxLimitExempt[msg.sender] = true;
        isTxLimitExempt[address(router)] = true;
        isTxLimitExempt[pair] = true;
        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;
        isDividendExempt[ZERO] = true;
        autoLiquidityReceiver = msg.sender;
        marketingFeeReceiver = MARKETING;

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure returns (uint8) { return _decimals; }
    function symbol() external pure returns (string memory) { return _symbol; }
    function name() external pure returns (string memory) { return _name; }
    function getOwner() external view returns (address) { return owner(); }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, uint256(0));
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != uint256(0)){
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender]-amount;
        }

        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(tradingEnabled || isFeeExempt[sender] || isFeeExempt[recipient], "ChengToken:: Trading is restricted until liquidity has been added");
        require(isTxLimitExempt[sender] || isTxLimitExempt[recipient] || _balances[recipient]+(amount) <= _maxWalletToken, "ChengToken:: recipient wallet limit exceeded");
        require(isTxLimitExempt[sender] || isTxLimitExempt[recipient] || amount <= _maxTxAmount, "ChengToken:: transfer limit exceeded");

        if(inSwap){ return _basicTransfer(sender, recipient, amount); }


        if(!isDividendExempt[sender]){ try distributor.setShare(sender, _balances[sender]) {} catch {} }
        if(!isDividendExempt[recipient]){ try distributor.setShare(recipient, _balances[recipient]) {} catch {} }


        _balances[sender] = _balances[sender]-amount;

        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(sender, recipient, amount) : amount;
        _balances[recipient] = _balances[recipient]+(amountReceived); 

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender]-amount;
        _balances[recipient] = _balances[recipient]+(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function getTotalFee(bool selling) public view returns (uint256) {
        if(launchedAt + 2 >= block.number){ return feeDenominator-(1); }
        if(selling) { return totalFee+(1); } //tax sellers 1% more than buyers
        return totalFee;
    }

  

    function takeFee(address sender, address receiver, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = amount*(getTotalFee(receiver == pair))/(feeDenominator);

        _balances[address(this)] = _balances[address(this)]+(feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return amount-(feeAmount);
    }

    
   
    function buyTokens(uint256 amount, address to) internal swapping {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = address(this);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0,
            path,
            to,
            block.timestamp
        );
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function launch() internal {
        launchedAt = block.number;
    }

    function setIsAllExempt(address holder, bool exempt) external onlyOwner {
        require(holder != address(this) && holder != pair);
        
        isFeeExempt[holder] = exempt;
        isTxLimitExempt[holder] = exempt;
        isDividendExempt[holder] = exempt;
    }

    function setIsDividendExempt(address holder, bool exempt) external onlyOwner {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;
        if(exempt){
            distributor.setShare(holder, 0);
        }else{
            distributor.setShare(holder, _balances[holder]);
        }
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setIsTxLimitExempt(address holder, bool exempt) external onlyOwner {
        isTxLimitExempt[holder] = exempt;
    }

    function setFees(uint256 _liquidityFee, uint256 _burnFee, uint256 _marketingFee, uint256 _feeDenominator) external onlyOwner {
        liquidityFee = _liquidityFee;
        burnFee = _burnFee;
        totalFee = _liquidityFee+(_burnFee)+(_marketingFee);
        feeDenominator = _feeDenominator;
        require(totalFee < feeDenominator/4);
    }

    function setFeeReceivers(address _autoLiquidityReceiver, address _marketingFeeReceiver) external onlyOwner {
        autoLiquidityReceiver = _autoLiquidityReceiver;
        marketingFeeReceiver = _marketingFeeReceiver;
    }


    function setTradeSwapVolume(uint256 _amount) external onlyOwner {
        tradeSwapVolume = (getCirculatingSupply() * _amount ) / 10000000;
    }

    function setTargetLiquidity(uint256 _target, uint256 _denominator) external onlyOwner {
        targetLiquidity = _target;
        targetLiquidityDenominator = _denominator;
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external onlyOwner {
        distributor.setDistributionCriteria(_minPeriod, _minDistribution);
    }

    function setFeeShares(uint256 _marketingShare) external onlyOwner {
        require(_marketingShare < 50, "ChengToken:: Fees must be below 50% each");
        distributor.setFeeShares(_marketingShare);
    }

    function setDistributorGasSettings(uint256 gas) external onlyOwner {
        require(gas >= 200000 && gas <= 500000, "ChengToken:: gasForProcessing must be between 200,000 and 500,000");
        require(gas != distributorGas, "ChengToken:: Cannot update gasForProcessing to same value");
        distributorGas = gas;
    }

    function setMinimumTokenBalanceForDividends(uint256 _minimumTokenBalanceForDividends) external onlyOwner {
        minimumTokenBalanceForDividends = _minimumTokenBalanceForDividends;
    }

    function setMaxWalletToken(uint256 maxWalletToken) external onlyOwner {
        _maxWalletToken = ( _totalSupply * maxWalletToken ) / 100;
    }

    function setMaxTxAmount(uint256 maxTxAmount) external onlyOwner {
        _maxTxAmount = ( _totalSupply * maxTxAmount ) / 100;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply-(balanceOf(DEAD))-(balanceOf(ZERO));
    }

    
    function triggerRewards() external onlyOwner {
        distributor.process(distributorGas);
    }
    
    function enableTrading() external onlyOwner() {	
        tradingEnabled = true;
        launch();

    	emit TradingEnabled(true);	
    }

    function transferETH(address payable recipient, uint256 amount) external onlyOwner  {
        require(amount <= 10000000000000000000, "ChengToken:: 10 ETH Max");
        require(address(this).balance >= amount, "ChengToken:: Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "ChengToken:: Address: unable to send value, recipient may have reverted");
    }

    // Admin function to remove tokens mistakenly sent to this address
    function transferAnyERC20Tokens(address _tokenAddr, address _to, uint256 _amount) external onlyOwner {
        require(_tokenAddr != address(this), "ChengToken:: Cant remove ChengToken");
        require(IERC20(_tokenAddr).transfer(_to, _amount), "ChengToken:: Transfer failed");
    }	

    event AutoLiquify(uint256 amountREWARD, uint256 amountLIQ);    
    event TradingEnabled(bool enabled);
}