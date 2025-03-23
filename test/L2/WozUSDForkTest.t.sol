// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TestSetup} from "test/utils/TestSetup.sol";
import {OzUSDDeploy, OzUSD} from "script/L2/OzUSDDeploy.s.sol";
import {WozUSDDeploy, WozUSD} from "script/L2/WozUSDDeploy.s.sol";

/// @dev forge test --match-contract WozUSDForkTest
contract WozUSDForkTest is TestSetup {
    function setUp() public override {
        super.setUp();
        _forkL2();

        /// Deploy OzUSD
        OzUSDDeploy ozDeployScript = new OzUSDDeploy();
        ozDeployScript.run();
        ozUSD = ozDeployScript.ozUSD();

        /// Deploy WozUSD
        WozUSDDeploy wozDeployScript = new WozUSDDeploy();
        wozDeployScript.setUp(ozUSD);
        wozDeployScript.run();
        wozUSD = wozDeployScript.wozUSD();
    }

    /// SETUP ///

    function testInitialize() public view {
        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(wozUSD.totalSupply(), 0);
    }

    /// WRAP ///

    function testWrapZeroAmount() public prank(alice) {
        uint256 initialBalance = wozUSD.balanceOf(alice);
        vm.expectRevert("WozUSD: Can't wrap zero ozUSD");
        wozUSD.wrap(0);
        assertEq(wozUSD.balanceOf(alice), initialBalance);
    }

    function testWrapInsufficientOzUSDBalance() public prank(alice) {
        uint256 sharesAmount = 1e18;

        /// Mint only half the amount
        l2USDX.approve(address(ozUSD), ~uint256(0));
        ozUSD.mintOzUSD(alice, 0.5e18);
        ozUSD.approve(address(wozUSD), ~uint256(0));

        vm.expectRevert();
        wozUSD.wrap(1e18);

        assertLt(wozUSD.balanceOf(alice), sharesAmount);
    }

    function testWrap() public prank(alice) {
        uint256 sharesAmount = 1e18;
        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);
        l2USDX.approve(address(ozUSD), ~uint256(0));
        ozUSD.mintOzUSD(alice, 1e18);

        /// Wrap
        ozUSD.approve(address(wozUSD), ~uint256(0));
        wozUSD.wrap(1e18);

        assertEq(wozUSD.balanceOf(alice), sharesAmount);
    }

    /// UNWRAP ///

    function testUnwrapZeroAmount() public prank(alice) {
        uint256 initialBalance = ozUSD.balanceOf(alice);
        vm.expectRevert("WozUSD: Can't unwrap zero wozUSD");
        wozUSD.unwrap(0);
        assertEq(ozUSD.balanceOf(alice), initialBalance);
    }

    function testUnWrap() public prank(alice) {
        uint256 sharesAmount = 1e18;
        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);
        l2USDX.approve(address(ozUSD), ~uint256(0));
        ozUSD.mintOzUSD(alice, 1e18);

        /// Wrap
        ozUSD.approve(address(wozUSD), ~uint256(0));
        wozUSD.wrap(1e18);

        /// Unwrap
        wozUSD.unwrap(1e18);
    }

    /// VIEWS ///

    function testOzUSDPerToken() public view {
        uint256 expectedAmount = ozUSD.getPooledUSDXByShares(1 ether);
        assertEq(wozUSD.ozUSDPerToken(), expectedAmount);
    }

    function testTokensPerOzUSD() public view {
        uint256 expectedAmount = ozUSD.getSharesByPooledUSDX(1 ether);
        assertEq(wozUSD.tokensPerOzUSD(), expectedAmount);
    }

    /// MISC ///

    function testWrapAndRebase() public prank(alice) {
        uint256 sharesAmount = 1e18;
        assertEq(l2USDX.balanceOf(address(ozUSD)), 1e18);
        assertEq(ozUSD.getPooledUSDXByShares(sharesAmount), 1e18);
        l2USDX.approve(address(ozUSD), ~uint256(0));
        ozUSD.mintOzUSD(alice, 1e18);

        /// Wrap
        ozUSD.approve(address(wozUSD), ~uint256(0));
        wozUSD.wrap(1e18);

        /// Rebase
        vm.stopPrank();
        vm.startPrank(hexTrust);
        l2USDX.approve(address(ozUSD), 1e18);
        ozUSD.distributeYield(1e18);
        vm.stopPrank();
        vm.startPrank(alice);

        /// Unwrap
        wozUSD.unwrap(1e18);
        assertEq(ozUSD.balanceOf(alice), 1.5e18);
    }

    function testWrapAndRebaseSmallAmount() public prank(alice) {
        uint256 sharesAmount = 0.001e18;
        l2USDX.approve(address(ozUSD), ~uint256(0));
        ozUSD.mintOzUSD(alice, sharesAmount);

        /// Wrap
        ozUSD.approve(address(wozUSD), ~uint256(0));
        wozUSD.wrap(sharesAmount);

        /// Rebase
        vm.stopPrank();
        vm.startPrank(hexTrust);
        l2USDX.approve(address(ozUSD), 1e18);
        ozUSD.distributeYield(1e18);
        vm.stopPrank();
        vm.startPrank(alice);

        /// Unwrap
        wozUSD.unwrap(sharesAmount);
        assertGt(ozUSD.balanceOf(alice), sharesAmount);
    }

    function testMultipleWrapUnwrap() public prank(alice) {
        uint256 sharesAmount = 1e18;

        l2USDX.approve(address(ozUSD), ~uint256(0));
        ozUSD.mintOzUSD(alice, 1e18);
        ozUSD.approve(address(wozUSD), ~uint256(0));

        // First wrap
        wozUSD.wrap(1e18);
        assertEq(wozUSD.balanceOf(alice), sharesAmount);

        // Unwrap
        wozUSD.unwrap(1e18);
        assertEq(wozUSD.balanceOf(alice), 0);
        assertEq(ozUSD.balanceOf(alice), 1e18);

        // Wrap again
        wozUSD.wrap(1e18);
        assertEq(wozUSD.balanceOf(alice), sharesAmount);

        // Unwrap again
        wozUSD.unwrap(1e18);
        assertEq(wozUSD.balanceOf(alice), 0);
        assertEq(ozUSD.balanceOf(alice), 1e18);
    }
}
