# Custom ERC20 token

Token for purchasign the NFT  

## Tokenomics:
- Total supply: 200M
- Minting of new tokens with a capped supply
- Burning of tokens with a capped supply
- Transfer to a specific wallet address
- Ownership transfer to a specific wallet address
- Admin of the smart contract through Ehterscan
- Set burning percentage rate: 0.5%
- Set liquidity pool percentage fee: 0.5%
- Set marketing percentage fee: 1%
- Disable/Enable marketing percentage

## How to deploy token  


    $ npm install @truffle/hdwallet-provider
    $ truffle deploy --network rinkeby
    $ truffle verify ChengToken --network rinkeby

## To be changed before publishing
- IERC20 REWARD = IERC20(0xc778417E063141139Fce010982780140Aa0cD5Ab);
- address WETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab; 
- marketingWallet = address(0x7488D2d66BdaEf675FBcCc5266d44C6EB313a97b);
