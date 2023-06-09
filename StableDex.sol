// SPDX-License-Identifier: MIT
//import "./lptoken.sol";
import "./interfaces/ILPToken.sol";
//import "./IERC20.sol";
import "./lptoken.sol";
//import "./interfaces/IWETH.sol";
import "./interfaces/IAMM.sol";
//import "./StableAlgorithm.sol";

pragma solidity ^0.8.17;

contract StableDex {
//全局变量


    address owner;
    uint constant ONE_ETH = 10 ** 18;
    mapping(address => address) pairCreator;//lpAddr pairCreator
    address [] public lpTokenAddressList;//lptoken的数组
    mapping(address => mapping(address => uint)) reserve;//第一个address是lptoken的address ，第2个是相应token的资产，uint是资产的amount
    uint userFee;//fee to pool
    //检索lptoken
    mapping(address => mapping(address => address)) findLpToken;
    //IWETH immutable WETH;
    //address immutable WETHAddr;
    //mapping (address => bool) public isStablePair;




    constructor()
    {
        owner = msg.sender;
    }

    receive() payable external {}

    modifier reEntrancyMutex() {
        bool _reEntrancyMutex;

        require(!_reEntrancyMutex,"FUCK");
        _reEntrancyMutex = true;
        _;
        _reEntrancyMutex = false;

    }

    modifier onlyOwner (){
        require(msg.sender == owner,"fuck");
        _;
    }

//管理人员权限
    function setFee(uint fee) external onlyOwner{
        userFee = fee;// dx / 10000
    }

//业务合约
    //添加流动性




    function addLiquidityWithStablePair(address _token0, address _token1, uint _amount0,uint _amount1) public returns (uint shares) {
        
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        
        require(_amount0 > 0 ,"require _amount0 > 0 && _amount1 >0");
        require(_token0 != _token1, "_token0 == _token1");
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        token0.transferFrom(msg.sender, address(this), _amount0);
        //token1.transferFrom(msg.sender, address(this), _amount1);
        address lptokenAddr;

        /*
        How much dx, dy to add?
        xy = k
        (x + dx)(y + dy) = k'
        No price change, before and after adding liquidity
        x / y = (x + dx) / (y + dy)
        x(y + dy) = y(x + dx)
        x * dy = y * dx
        x / y = dx / dy
        dy = y / x * dx
        */
        //问题：
        /*
        如果项目方撤出所有流动性后会存在问题
        1.添加流动性按照比例 0/0 会报错

        解决方案：
        每次添加至少n个token
        且remove流动性至少保留n给在amm里面

        */
        if (findLpToken[_token1][_token0] != address(0)) {
            lptokenAddr = findLpToken[_token1][_token0];
            _amount1 = calOutput(100,reserve[lptokenAddr][_token0] + reserve[lptokenAddr][_token1], reserve[lptokenAddr][_token0],_amount0);


            token1.transferFrom(msg.sender, address(this), _amount1);
            //require(reserve0[lptokenAddr][_token0] * _amount1 == reserve1[lptokenAddr][_token1] * _amount0, "x / y != dx / dy");
            //必须保持等比例添加，添加后k值会改变
        }

        if (findLpToken[_token1][_token0] == address(0)) {
            //当lptoken = 0时，创建lptoken
            shares = _sqrt(_amount0 * _amount1);
            createPair(_token0,_token1);
            lptokenAddr = findLpToken[_token1][_token0];
            lptoken = ILPToken(lptokenAddr);//获取lptoken地址
            pairCreator[lptokenAddr] = msg.sender;
            token1.transferFrom(msg.sender, address(this), _amount1);

            //isStablePair[lptokenAddr] = true;
            
        } else {
            lptoken = ILPToken(lptokenAddr);//获取lptoken地址
            shares = _min(
                (_amount0 * lptoken.totalSupply()) / reserve[lptokenAddr][_token0],
                (_amount1 * lptoken.totalSupply()) / reserve[lptokenAddr][_token1]
            );
            //获取lptoken地址
        }
        require(shares > 0, "shares = 0");
        lptoken.mint(msg.sender,shares);
        

        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] + _amount0, reserve[lptokenAddr][_token1] + _amount1);

    }
    //移除流动性

    function removeLiquidity(
        address _token0,
        address _token1,
        uint _shares
    ) public  returns (uint amount0, uint amount1) {
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        address lptokenAddr = findLpToken[_token0][_token1];

        lptoken = ILPToken(lptokenAddr);

        if(pairCreator[lptokenAddr] == msg.sender)
        {
            require(lptoken.balanceOf(msg.sender) - _shares > 100 ,"paieCreator should left 100 wei lptoken in pool");
        }

        amount0 = (_shares * reserve[lptokenAddr][_token0]) / lptoken.totalSupply();//share * totalsuply/bal0
        amount1 = (_shares * reserve[lptokenAddr][_token1]) / lptoken.totalSupply();
        require(amount0 > 0 && amount1 > 0, "amount0 or amount1 = 0");

        lptoken.burn(msg.sender, _shares);
        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] - amount0, reserve[lptokenAddr][_token1] - amount1);
        

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

    //交易





    function swapByStableCoin(address _tokenIn, address _tokenOut, uint _amountIn, uint _disirSli) public returns(uint amountOut){
        require(
            findLpToken[_tokenIn][_tokenOut] != address(0),
            "invalid token"
        );
        require(_amountIn > 0, "amount in = 0");
        require(_tokenIn != _tokenOut);
        require(_amountIn >= 100, "require amountIn >= 100 wei token");
        //require(isStablePair[findLpToken[_tokenIn][_tokenOut]],"not stablePair");

        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);
        address lptokenAddr = findLpToken[_tokenIn][_tokenOut];
        uint reserveIn = reserve[lptokenAddr][_tokenIn];
        uint reserveOut = reserve[lptokenAddr][_tokenOut];
        //require(isStablePair[lptokenAddr],"not stablePair");

        tokenIn.transferFrom(msg.sender, address(this), _amountIn);


        //交易税收 
        uint amountInWithFee = (_amountIn * (100000-userFee)) / 100000;
        //amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
        amountOut = calOutput(100,reserveIn + reserveOut, reserveIn,amountInWithFee);

        //检查滑点
        //setSli(amountInWithFee,reserveIn,reserveOut,_disirSli);
        setSliBystable(amountOut,amountInWithFee,reserveIn,reserveOut,_disirSli);


        tokenOut.transfer(msg.sender, amountOut);
        uint totalReserve0 = reserve[lptokenAddr][_tokenIn] + _amountIn; 
        uint totalReserve1 = reserve[lptokenAddr][_tokenOut] - amountOut;

        _update(lptokenAddr,_tokenIn, _tokenOut, totalReserve0, totalReserve1);

    }

    function swapByStableCoin2(address _tokenIn, address _tokenOut, uint _amountIn) public returns(uint amountOut){
        require(
            findLpToken[_tokenIn][_tokenOut] != address(0),
            "invalid token"
        );
        require(_amountIn > 0, "amount in = 0");
        require(_tokenIn != _tokenOut);
        require(_amountIn >= 100, "require amountIn >= 100 wei token");
        //require(isStablePair[findLpToken[_tokenIn][_tokenOut]],"not stablePair");

        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);
        address lptokenAddr = findLpToken[_tokenIn][_tokenOut];
        uint reserveIn = reserve[lptokenAddr][_tokenIn];
        uint reserveOut = reserve[lptokenAddr][_tokenOut];
        //require(isStablePair[lptokenAddr],"not stablePair");

        tokenIn.transferFrom(msg.sender, address(this), _amountIn);


        //交易税收 
        uint amountInWithFee = (_amountIn * (100000-userFee)) / 100000;
        //amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
        amountOut = calOutput(100,reserveIn + reserveOut, reserveIn,amountInWithFee);

        //检查滑点
        //setSli(amountInWithFee,reserveIn,reserveOut,_disirSli);


        tokenOut.transfer(msg.sender, amountOut);
        uint totalReserve0 = reserve[lptokenAddr][_tokenIn] + _amountIn; 
        uint totalReserve1 = reserve[lptokenAddr][_tokenOut] - amountOut;

        _update(lptokenAddr,_tokenIn, _tokenOut, totalReserve0, totalReserve1);

    }

    //暴露数据查询方法

    function getReserve(address _lpTokenAddr, address _tokenAddr) public view returns(uint)
    {
        return reserve[_lpTokenAddr][_tokenAddr];
    }

    function getLptoken(address _tokenA, address _tokenB) public view returns(address)
    {
        return findLpToken[_tokenA][_tokenB];
    }

    function lptokenTotalSupply(address _token0, address _token1, address user) public view returns(uint)
    {
        ILPToken lptoken;
        lptoken = ILPToken(findLpToken[_token0][_token1]);
        uint totalSupply = lptoken.balanceOf(user);
        return totalSupply;
    }

    function getLptokenLength() public view returns(uint)
    {
        return lpTokenAddressList.length;
    }

//依赖方法
    //creatpair

    function createPair(address addrToken0, address addrToken1) internal returns(address){
        bytes32 _salt = keccak256(
            abi.encodePacked(
                addrToken0,addrToken1
            )
        );
        new LPToken{
            salt : bytes32(_salt)
        }
        ();
        address lptokenAddr = getAddress(getBytecode(),_salt);

         //检索lptoken
        lpTokenAddressList.push(lptokenAddr);
        findLpToken[addrToken0][addrToken1] = lptokenAddr;
        findLpToken[addrToken1][addrToken0] = lptokenAddr;

        return lptokenAddr;
    }

    function getBytecode() internal pure returns(bytes memory) {
        bytes memory bytecode = type(LPToken).creationCode;
        return bytecode;
    }

    function getAddress(bytes memory bytecode, bytes32 _salt)
        internal
        view
        returns(address)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(this), _salt, keccak256(bytecode)
            )
        );

        return address(uint160(uint(hash)));
    }

    //数据更新

    function _update(address lptokenAddr,address _token0, address _token1, uint _reserve0, uint _reserve1) private {
        reserve[lptokenAddr][_token0] = _reserve0;
        reserve[lptokenAddr][_token1] = _reserve1;
    }

//数学库

    function cacalTokenOutAmount(address _tokenIn, address _tokenOut, uint _tokenInAmount) public view returns(uint tokenOutAmount)
    {
        address lptokenAddr = getLptoken(_tokenIn,_tokenOut);
        uint reserveIn = getReserve(lptokenAddr, _tokenIn);
        uint reserveOut = getReserve(lptokenAddr,_tokenOut);

        tokenOutAmount = (reserveOut * _tokenInAmount) / (reserveIn + _tokenInAmount);
    }

    function _sqrt(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }


    function setSliBystable(uint _amountOut,uint dx, uint x, uint y, uint _disirSli) public pure returns(uint){


        uint amountOut = _amountOut;

        uint dy = dx * y/x;
        /*
        loseAmount = Idea - ammOut
        Sli = loseAmount/Idea
        Sli = [dx*y/x - y*dx/(dx + x)]/dx*y/x
        */
        uint loseAmount = dy - amountOut;

        uint Sli = loseAmount * 100000 /dy;
        
        require(Sli <= _disirSli, "Sli too large");
        return Sli;


    }

// SPDX-License-Identifier: MIT




    /*
    \frac{-4ADx^2-4x+4AD^2x+\sqrt{\left(4ADx^2+4x-4AD^2x\right)^2+16AD^3x}}{8ADx}

    \frac{-4ADx^2-4x+4AD^2x+\sqrt{\left(4ADx^2+4x-4AD^2x\right)^2+16AD^3x}}{8ADx}

    y=(4*A*D*D*X-4*X-4*A*D*X*X + calSqrt(A, D, X))/8*A*D*X
    dy = y - (4*A*D*D*X-4*X-4*A*D*X*X + calSqrt(A, D, X))/8*A*D*X
    */







    function calOutAmount(uint A, uint D, uint X)public pure returns(uint)
    {
        //return  (4*A*D*D*X+calSqrt(A, D, X) -4*X-4*A*D*X*X) / (8*A*D*X);
        uint a = 4*A*D*X+D*calSqrt(A, D, X)-4*A*X*X-D*X;
        //uint amountOut2 = y - amountOut1;
        return a/(8*A*X);

    }

    function calOutput(uint A, uint D, uint X,uint dx)public pure returns(uint)
    {
        //D = D * 10**18;
        //X = X * 10**18;
        //dx = dx* 10**18;
        uint S = X + dx;
        uint amount1 = calOutAmount(A, D, X);
        uint amount2 = calOutAmount(A, D, S);

        //uint amountOut2 = y - amountOut1;
        return amount1 - amount2;

    }

    


    function calSqrt(uint A, uint D, uint X)public pure returns(uint)
    {
        //uint T = t(A,D,X);
        //uint calSqrtNum = _sqrt((X*(4+T))*(X*(4+T))+T*T*D*D+4*T*D*D-2*X*T*D*(4+T));
        //return calSqrtNum;
        (uint a, uint b) = (4*A*X*X/D+X,4*A*X);
        uint c;
        if(a>=b){
            c = a -b;
        }else{
            c = b-a;
        }

        return _sqrt(c*c+4*D*X*A);

    }














}
