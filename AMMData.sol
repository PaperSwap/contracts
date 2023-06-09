// SPDX-License-Identifier: MIT

import "./IAMM.sol";
import "./StableAlgorithm.sol";
import "./interfaces/ILPToken.sol";
import "./IERC20.sol";

pragma solidity ^0.8.9;


contract AMMData{
    IAMM amm;
    uint constant ONE_ETH = 10 ** 18;
    constructor(address _amm){
        amm = IAMM(_amm);

    }

    function resetAmm(address _amm) public {
        amm = IAMM(_amm);
    }

    function getTokenPrice(address _tokenA, address _tokenB) public view returns(uint reserveA,uint reserveB, uint one_tokenA_price,uint one_tokenB_price)
    {
        address lptokenAddr = amm.getLptoken(_tokenA,_tokenB);
        reserveA = amm.getReserve(lptokenAddr, _tokenA);
        reserveB = amm.getReserve(lptokenAddr,_tokenB);

        one_tokenA_price = reserveB * ONE_ETH / reserveA;
        one_tokenB_price = reserveA * ONE_ETH / reserveB;

            
    }

    function getTokenPriceStableCoin(address _tokenA, address _tokenB, uint amountIn) public view returns(uint reserveA,uint reserveB, uint tokenA_price,uint tokenB_price)
    {
        address lptokenAddr = amm.getLptoken(_tokenA,_tokenB);
        reserveA = amm.getReserve(lptokenAddr, _tokenA);
        reserveB = amm.getReserve(lptokenAddr,_tokenB);
        tokenA_price = StableAlgorithm.calOutput(amm.getA(lptokenAddr),reserveA + reserveB, reserveA,amountIn);
        tokenB_price = StableAlgorithm.calOutput(amm.getA(lptokenAddr),reserveA + reserveB, reserveB,amountIn);

        
        //tokenOutAmount = StableAlgorithm.calOutput(100,reserveA + reserveB, reserveA,_tokenInAmount);



            
    }

    function cacalTokenOutAmount(address _tokenIn, address _tokenOut, uint _tokenInAmount) public view returns(uint tokenOutAmount)
    {
        address lptokenAddr = amm.getLptoken(_tokenIn,_tokenOut);
        uint reserveIn = amm.getReserve(lptokenAddr, _tokenIn);
        uint reserveOut = amm.getReserve(lptokenAddr,_tokenOut);
        if(amm.isStablePair(lptokenAddr)){

            tokenOutAmount = StableAlgorithm.calOutput(amm.getA(lptokenAddr),reserveIn + reserveOut, reserveIn,_tokenInAmount);
        }else{
            tokenOutAmount = (reserveOut * _tokenInAmount) / (reserveIn + _tokenInAmount);
        }
    }

    function cacalLpTokenAddAmount(address _tokenA, address _tokenB, uint _amountA) public view returns(uint _amountB)
    {
        address lptokenAddr = amm.getLptoken(_tokenA,_tokenB);
        _amountB = amm.getReserve(lptokenAddr,_tokenB) * _amountA / amm.getReserve(lptokenAddr, _tokenA);
    }

 

    function getRemoveLiquidityAmount(
        address _token0,
        address _token1,
        uint _shares
    ) public view  returns (uint amount0, uint amount1) {
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        address lptokenAddr = amm.getLptoken(_token0,_token1);

        lptoken = ILPToken(lptokenAddr);


        amount0 = (_shares * amm.getReserve(lptokenAddr,_token0)) / lptoken.totalSupply();//share * totalsuply/bal0
        amount1 = (_shares * amm.getReserve(lptokenAddr,_token1)) / lptoken.totalSupply();
    }

    

    
}
