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

# How to deploy token  


    $ npm install @truffle/hdwallet-provider
    $ truffle deploy --network rinkeby
    $ truffle verify ChengToken --network rinkeby

