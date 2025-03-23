// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TestSetup, IUSDX} from "test/utils/TestSetup.sol";
import {OzUSDDeploy, OzUSD} from "script/L2/OzUSDDeploy.s.sol";

/// @dev forge test --match-contract OzUSDForkTest
contract OzUSDForkTest is TestSetup {
    event TransferShares(address indexed from, address indexed to, uint256 sharesValue);
    event SharesBurnt(
        address indexed account, uint256 preRebaseTokenAmount, uint256 postRebaseTokenAmount, uint256 sharesAmount
    );
    event YieldDistributed(uint256 _previousTotalBalance, uint256 _newTotalBalance);

    function setUp() public override {
        super.setUp();
        _forkL2();

        /// Deploy ozUSD
        OzUSDDeploy deployScript = new OzUSDDeploy();
        deployScript.run();
        ozUSD = deployScript.ozUSD();

        //deal(address(l2USDX), hexTrust, 1000e18);
    }

    /// SETUP ///

    function testInitialize() public view {
        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(ozUSD.balanceOf(address(0xdead)), 1e18);
        assertEq(ozUSD.totalSupply(), 1e18);
        assertEq(ozUSD.name(), "Ozean USD");
        assertEq(ozUSD.symbol(), "ozUSD");
        assertEq(ozUSD.decimals(), 18);
    }

    function testDeployRevertConditions() public prank(hexTrust) {
        uint256 initialSharesAmount = 1e18;

        /// Deploy with less than 1 USDX
        vm.expectRevert("OzUSD: Must deploy with at least one USDX.");
        new OzUSD(hexTrust, address(l2USDX), initialSharesAmount - 1);

        // Allowance
        vm.expectRevert("ERC20: insufficient allowance");
        new OzUSD(hexTrust, address(l2USDX), initialSharesAmount);

        /// Success
        address predictedAddress = vm.computeCreateAddress(hexTrust, vm.getNonce(hexTrust));
        l2USDX.approve(predictedAddress, 1e18);
        new OzUSD(hexTrust, address(l2USDX), initialSharesAmount);
    }

    /// REBASE ///

    function testMintRevertConditions() public prank(alice) {
        /// Amount zero
        vm.expectRevert("OzUSD: Amount zero.");
        ozUSD.mintOzUSD(alice, 0);

        /// Allowance
        vm.expectRevert("ERC20: insufficient allowance");
        ozUSD.mintOzUSD(alice, 1e18 + 1);

        l2USDX.approve(address(ozUSD), 1e36);

        /// Mint to zero address
        vm.expectRevert("OzUSD: Mint to zero address.");
        ozUSD.mintOzUSD(address(0), 1e18);
    }

    function testRedeemOzUSDRevertConditions() public prank(alice) {
        uint256 _amountA = 100 ether;

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        l2USDX.approve(address(ozUSD), _amountA);
        ozUSD.mintOzUSD(alice, _amountA);

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18 + _amountA);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        /// Amount zero
        vm.expectRevert("OzUSD: Amount zero.");
        ozUSD.redeemOzUSD(alice, 0);

        /// Burn more than allowance
        vm.expectRevert("OzUSD: Balance exceeded.");
        ozUSD.redeemOzUSD(alice, 1e30);

        /// Allowance
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("OzUSD: Allowance exceeded.");
        ozUSD.redeemOzUSD(alice, 1e30);
    }

    function testRebase() public prank(hexTrust) {
        uint256 amount = 100 ether;
        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(amount), amount);

        /// Allowance
        vm.expectRevert("ERC20: insufficient allowance");
        ozUSD.distributeYield(1e18);

        l2USDX.approve(address(ozUSD), amount);

        /// Rebase
        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(1e18, 1e18 + amount);
        ozUSD.distributeYield(amount);

        assertEq(ozUSD.getPooledUSDXByShares(amount), (amount * l2USDX.balanceOf(address(ozUSD))) / 1e18);
    }

    function testMintAndRebase() public prank(alice) {
        uint256 _amountA = 100 ether;
        uint256 _amountB = 250 ether;

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        l2USDX.approve(address(ozUSD), _amountA);
        ozUSD.mintOzUSD(alice, _amountA);

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18 + _amountA);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        vm.stopPrank();
        vm.startPrank(hexTrust);

        l2USDX.approve(address(ozUSD), _amountB);

        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(1e18 + _amountA, 1e18 + _amountA + _amountB);
        ozUSD.distributeYield(_amountB);

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18 + _amountA + _amountB);
        assertEq(ozUSD.balanceOf(alice), ozUSD.getPooledUSDXByShares(_amountA));
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), (_amountA * (1e18 + _amountA + _amountB)) / (1e18 + _amountA));
    }

    function testMintAndRedeem() public prank(alice) {
        uint256 _amountA = 100 ether;

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        l2USDX.approve(address(ozUSD), _amountA);
        ozUSD.mintOzUSD(alice, _amountA);

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18 + _amountA);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        ozUSD.approve(alice, _amountA);
        ozUSD.redeemOzUSD(alice, _amountA);

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(ozUSD.balanceOf(alice), 0);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);
    }

    function testMintRebaseAndRedeem() public prank(alice) {
        uint256 _amountA = 100 ether;
        uint256 _amountB = 250 ether;

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        l2USDX.approve(address(ozUSD), _amountA);
        ozUSD.mintOzUSD(alice, _amountA);

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18 + _amountA);
        assertEq(ozUSD.balanceOf(alice), _amountA);
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), _amountA);

        vm.stopPrank();
        vm.startPrank(hexTrust);

        l2USDX.approve(address(ozUSD), _amountB);

        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(1e18 + _amountA, 1e18 + _amountA + _amountB);
        ozUSD.distributeYield(_amountB);

        vm.stopPrank();
        vm.startPrank(alice);

        uint256 predictedAliceAmount = (_amountA * (1e18 + _amountA + _amountB)) / (1e18 + _amountA);

        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18 + _amountA + _amountB);
        assertEq(ozUSD.balanceOf(alice), ozUSD.getPooledUSDXByShares(_amountA));
        assertEq(ozUSD.getPooledUSDXByShares(_amountA), predictedAliceAmount);

        ozUSD.approve(alice, predictedAliceAmount);
        ozUSD.redeemOzUSD(alice, predictedAliceAmount);
        assertEq(l2USDX.balanceOf(address(ozUSD)), (1e18 + _amountA + _amountB) - predictedAliceAmount);
    }

    /// ERC20 ///

    function testApproveRevertConditions() public prank(address(0)) {
        /// Approve from zero address
        vm.expectRevert("OzUSD: Approve from zero address.");
        ozUSD.approve(alice, 1e18);

        vm.stopPrank();
        vm.startPrank(alice);

        /// Approve to zero address
        vm.expectRevert("OzUSD: Approve to zero address.");
        ozUSD.approve(address(0), 1e18);
    }

    function testApproveAndTransferFrom() public prank(alice) {
        uint256 sharesAmount = 1e18;

        // Ensure initial balance
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);

        // Mint ozUSD
        l2USDX.approve(address(ozUSD), 1e18);
        ozUSD.mintOzUSD(alice, 1e18);
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
        l2USDX.approve(address(ozUSD), 1e18);
        ozUSD.mintOzUSD(alice, 1e18);
        assertEq(ozUSD.balanceOf(alice), 1e18);

        // Increase Bob's allowance
        ozUSD.increaseAllowance(bob, 0.5e18);
        assertEq(ozUSD.allowance(alice, bob), 0.5e18);

        // Decrease Bob's allowance
        ozUSD.decreaseAllowance(bob, 0.2e18);
        assertEq(ozUSD.allowance(alice, bob), 0.3e18);

        /// Decrease Bob's allowance revert
        vm.expectRevert("OzUSD: Allowance below value.");
        ozUSD.decreaseAllowance(bob, 0.4e18);
    }

    function testTransferSharesRevertConditions() public prank(address(0)) {
        /// Transfer from zero address
        vm.expectRevert("OzUSD: Transfer from zero address.");
        ozUSD.transferShares(alice, 1e18);

        /// Transfer to zero address
        vm.stopPrank();
        vm.startPrank(alice);

        vm.expectRevert("OzUSD: Transfer to zero address.");
        ozUSD.transferShares(address(0), 1e18);

        /// Transfer to contract.
        vm.expectRevert("OzUSD: Transfer to this contract.");
        ozUSD.transferShares(address(ozUSD), 1e18);
    }

    function testTransferShares() public prank(alice) {
        // Mint ozUSD
        l2USDX.approve(address(ozUSD), 1e18);
        ozUSD.mintOzUSD(alice, 1e18);
        assertEq(ozUSD.sharesOf(alice), 1e18);

        /// Burn zero revert
        vm.expectRevert("OzUSD: Transfer zero shares.");
        ozUSD.transferShares(alice, 0);

        // Transfer shares from alice to bob
        uint256 sharesToTransfer = 0.5e18;
        uint256 tokensTransferred = ozUSD.transferShares(bob, sharesToTransfer);

        // Check balances after the transfer
        assertEq(ozUSD.balanceOf(alice), 0.5e18);
        assertEq(ozUSD.balanceOf(bob), tokensTransferred);
        assertEq(ozUSD.sharesOf(alice), 0.5e18);
        assertEq(ozUSD.sharesOf(bob), 0.5e18);
    }

    function testTransferSharesFrom() public prank(alice) {
        // Mint ozUSD
        l2USDX.approve(address(ozUSD), 1e18);
        ozUSD.mintOzUSD(alice, 1e18);

        // Transfer shares from alice to bob
        uint256 sharesToTransfer = 0.5e18;
        ozUSD.approve(alice, ~uint256(0));
        uint256 tokensTransferred = ozUSD.transferSharesFrom(alice, bob, sharesToTransfer);

        // Check balances after the transfer
        assertEq(ozUSD.balanceOf(alice), 0.5e18);
        assertEq(ozUSD.balanceOf(bob), tokensTransferred);
    }

    function testTransferMoreThanBalanceReverts() public prank(alice) {
        // Mint ozUSD
        l2USDX.approve(address(ozUSD), 1e18);
        ozUSD.mintOzUSD(alice, 1e18);

        // Attempt to transfer more than alice's balance
        vm.expectRevert("OzUSD: Balance exceeded.");
        ozUSD.transfer(bob, 2e18); // Transfer amount exceeds balance
    }

    function testBurnShares() public prank(alice) {
        uint256 sharesAmount = 1e18;

        // Mint ozUSD
        l2USDX.approve(address(ozUSD), 1e18);
        ozUSD.mintOzUSD(alice, 1e18);
        assertEq(ozUSD.balanceOf(alice), 1e18);

        /// Burn zero revert
        vm.expectRevert("OzUSD: Amount zero.");
        ozUSD.redeemOzUSD(alice, 0);

        // Burn half of the shares
        ozUSD.redeemOzUSD(alice, 0.5e18);

        // Check balances after burning
        assertEq(ozUSD.balanceOf(alice), 0.5e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);
    }

    function testAllowanceExceeded() public prank(alice) {
        l2USDX.approve(address(ozUSD), 1e18);
        ozUSD.mintOzUSD(alice, 1e18);

        // Alice approves Bob to spend 0.5 ozUSD
        ozUSD.approve(bob, 5e17);
        assertEq(ozUSD.allowance(alice, bob), 5e17);

        // Bob tries to transfer more than allowed, should fail
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("OzUSD: Allowance exceeded.");
        ozUSD.transferFrom(alice, bob, 1e18);
    }

    /// OWNER ///

    function testPaused() public prank(alice) {
        assertEq(ozUSD.paused(), false);

        /// Revert for non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        ozUSD.setPaused(true);

        vm.stopPrank();
        vm.startPrank(hexTrust);

        ozUSD.setPaused(true);
        assertEq(ozUSD.paused(), true);

        vm.expectRevert("Pausable: paused");
        ozUSD.mintOzUSD(alice, 1);

        ozUSD.setPaused(false);
        assertEq(ozUSD.paused(), false);
    }

    function testDistributeYield() public prank(alice) {
        /// Revert for non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        ozUSD.distributeYield(1 ether);

        vm.stopPrank();
        vm.startPrank(hexTrust);

        /// Owner
        l2USDX.approve(address(ozUSD), 1 ether);
        ozUSD.distributeYield(1 ether);
    }
}
