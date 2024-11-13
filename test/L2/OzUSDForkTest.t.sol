// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {TestSetup} from "test/utils/TestSetup.sol";
import {OzUSDDeploy, OzUSD, TransparentUpgradeableProxy} from "script/L2/OzUSDDeploy.s.sol";

/// @dev forge test --match-contract OzUSDForkTest
contract OzUSDForkTest is TestSetup {
    event TransferShares(address indexed from, address indexed to, uint256 sharesValue);
    event SharesBurnt(address indexed account, uint256 preRebaseTokenAmount, uint256 postRebaseTokenAmount, uint256 sharesAmount);
    event YieldDistributed(uint256 _previousTotalBalance, uint256 _newTotalBalance);

    OzUSD public implementation;

    function setUp() public override {
        super.setUp();
        _forkL2();

        OzUSDDeploy deployScript = new OzUSDDeploy();
        deployScript.run();
        implementation = deployScript.implementation();
        ozUSD = OzUSD(payable(deployScript.proxy()));
    }

    /// SETUP ///

    function testInitialize() public view {
        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.totalSupply(), 1e18);
        assertEq(ozUSD.name(), "Ozean USD");
        assertEq(ozUSD.symbol(), "ozUSD");
        assertEq(ozUSD.decimals(), 18);
    }

    /// REBASE ///

    function testRebase() public prank(alice) {
        uint256 amount = 100 ether;
        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(amount), amount);

        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(1e18, 1e18 + amount);
        ozUSD.distributeYield{value: amount}();

        assertEq(ozUSD.getPooledUSDXByShares(amount), (amount * address(ozUSD).balance) / 1e18);
    }

    function testMintAndRebase() public prank(alice) {
        uint256 _amountA = 100 ether;
        uint256 _amountB = 250 ether;

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        ozUSD.mintOzUSD{ value: _amountA }(alice, _amountA);

        assertEq(address(ozUSD).balance, 1e18 + _amountA);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(1e18 + _amountA, 1e18 + _amountA + _amountB);
        ozUSD.distributeYield{value: _amountB}();

        assertEq(address(ozUSD).balance, 1e18 + _amountA + _amountB);
        assertEq(ozUSD.balanceOf(alice), ozUSD.getPooledUSDXByShares(_amountA));
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), (_amountA * (1e18 + _amountA + _amountB)) / (1e18 + _amountA));
    }

    function testMintAndRedeem() public prank(alice) {
        uint256 _amountA = 100 ether;

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        ozUSD.mintOzUSD{ value: _amountA }(alice, _amountA);

        assertEq(address(ozUSD).balance, 1e18 + _amountA);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        ozUSD.approve(alice, _amountA);
        ozUSD.redeemOzUSD(alice, _amountA);

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.balanceOf(alice), 0);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);
    }

    function testMintRebaseAndRedeem() public prank(alice) {
        uint256 _amountA = 100 ether;
        uint256 _amountB = 250 ether;

        assertEq(address(ozUSD).balance, 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        ozUSD.mintOzUSD{ value: _amountA }(alice, _amountA);

        assertEq(address(ozUSD).balance, 1e18 + _amountA);
        assertEq(ozUSD.balanceOf(alice), _amountA);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(1e18 + _amountA, 1e18 + _amountA + _amountB);
        ozUSD.distributeYield{value: _amountB}();

        uint256 predictedAliceAmount = (_amountA * (1e18 + _amountA + _amountB)) / (1e18 + _amountA);

        assertEq(address(ozUSD).balance, 1e18 + _amountA + _amountB);
        assertEq(ozUSD.balanceOf(alice), ozUSD.getPooledUSDXByShares(_amountA));
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), predictedAliceAmount);

        ozUSD.approve(alice, predictedAliceAmount);
        ozUSD.redeemOzUSD(alice, predictedAliceAmount);
        assertEq(address(ozUSD).balance, (1e18 + _amountA + _amountB) - predictedAliceAmount);
    }

    /// ERC20 ///

    function testApproveAndTransferFrom() public prank(alice) {
        uint256 sharesAmount = 1e18;

        // Ensure initial balance
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        // Mint ozUSD
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);
        assertEq(ozUSD.balanceOf(alice), 1e18);

        // Approve bob to spend alice's ozUSD
        ozUSD.approve(bob, 0.5e18);
        assertEq(ozUSD.allowance(alice, bob), 0.5e18);

        // Bob transfers 0.5e18 ozUSD from alice to charlie
        address charlie = address(77);
        vm.stopPrank();
        vm.prank(bob);
        ozUSD.transferFrom(alice, charlie, 0.5e18);

        assertEq(ozUSD.balanceOf(alice), 0.5e18);
        assertEq(ozUSD.balanceOf(charlie), 0.5e18);
        assertEq(ozUSD.allowance(alice, bob), 0); // Full amount transferred
    }

    function testIncreaseAndDecreaseAllowance() public prank(alice) {
        // Mint ozUSD
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);
        assertEq(ozUSD.balanceOf(alice), 1e18);

        // Increase bob's allowance
        ozUSD.increaseAllowance(bob, 0.5e18);
        assertEq(ozUSD.allowance(alice, bob), 0.5e18);

        // Decrease bob's allowance
        ozUSD.decreaseAllowance(bob, 0.2e18);
        assertEq(ozUSD.allowance(alice, bob), 0.3e18);
    }

    function testTransferShares() public prank(alice) {
        // Mint ozUSD
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        // Transfer shares from alice to bob
        uint256 sharesToTransfer = 0.5e18;
        uint256 tokensTransferred = ozUSD.transferShares(bob, sharesToTransfer);

        // Check balances after the transfer
        assertEq(ozUSD.balanceOf(alice), 0.5e18);
        assertEq(ozUSD.balanceOf(bob), tokensTransferred);
    }

    function testTransferMoreThanBalanceReverts() public prank(alice) {
        // Mint ozUSD
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        // Attempt to transfer more than alice's balance
        vm.expectRevert("OzUSD: BALANCE_EXCEEDED");
        ozUSD.transfer(bob, 2e18); // Transfer amount exceeds balance
    }

    function testBurnShares() public prank(alice) {
        uint256 sharesAmount = 1e18;

        // Mint ozUSD
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);
        assertEq(ozUSD.balanceOf(alice), 1e18);

        // Burn half of the shares
        ozUSD.approve(alice, 0.5e18);
        ozUSD.redeemOzUSD(alice, 0.5e18);

        // Check balances after burning
        assertEq(ozUSD.balanceOf(alice), 0.5e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);
    }

    function testAllowanceExceeded() public prank(alice) {
        ozUSD.mintOzUSD{ value: 1e18 }(alice, 1e18);

        // Alice approves Bob to spend 0.5 ozUSD
        ozUSD.approve(bob, 5e17);
        assertEq(ozUSD.allowance(alice, bob), 5e17);

        // Bob tries to transfer more than allowed, should fail
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("OzUSD: ALLOWANCE_EXCEEDED");
        ozUSD.transferFrom(alice, bob, 1e18);
    }

    /// PROXY ///

    /// @dev Can only be called by admin, otherwise delegatecalls to impl
    function testAdmin() public prank(hexTrust) {
        assertEq(TransparentUpgradeableProxy(payable(ozUSD)).admin(), hexTrust);
    }

    function testProxyInitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize{ value: 1e18 }(1e18);

        assertEq(address(implementation).balance, 0);

        vm.expectRevert("Initializable: contract is already initialized");
        ozUSD.initialize{ value: 1e18 }(1e18);

        assertEq(address(ozUSD).balance, 1e18);
    }

    function testUpgradeImplementation() public prank(hexTrust) {
        OzUSD newImplementation = new OzUSD();

        assertEq(TransparentUpgradeableProxy(payable(ozUSD)).implementation(), address(implementation));

        TransparentUpgradeableProxy(payable(ozUSD)).upgradeToAndCall(address(newImplementation), "");

        assertEq(TransparentUpgradeableProxy(payable(ozUSD)).implementation(), address(newImplementation));
    }
}