// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {TestSetup, USDXBridge} from "test/utils/TestSetup.sol";
import {TestERC20Decimals, TestERC20DecimalsFeeOnTransfer} from "test/utils/Mocks.sol";
import {LGEStakingDeploy, LGEStaking} from "script/L1/LGEStakingDeploy.s.sol";
import {LGEMigrationDeploy, LGEMigrationV1} from "script/L1/LGEMigrationDeploy.s.sol";

/// @dev forge test --match-contract LGEStakingForkSepoliaTest
contract LGEStakingForkSepoliaTest is TestSetup {
    address[] public l1Addresses;
    address[] public l2Addresses;
    address[] public restrictedL2Addresses;
    uint256[] public depositCaps;

    function setUp() public override {
        super.setUp();
        _forkL1Sepolia();

        /// @dev Replace USDXBridge for migration tests
        usdxBridge = USDXBridge(0x084C27a0bE5dF26ed47F00678027A6E76B14a0B4);

        /// Deploy LGEStaking
        l1Addresses = new address[](4);
        l1Addresses[0] = address(usdc);
        l1Addresses[1] = address(usdt);
        l1Addresses[2] = address(dai);
        l1Addresses[3] = address(wstETH);

        depositCaps = new uint256[](4);
        depositCaps[0] = 1e12;
        depositCaps[1] = 1e12;
        depositCaps[2] = 1e24;
        depositCaps[3] = 1e24;

        LGEStakingDeploy stakingDeployScript = new LGEStakingDeploy();
        stakingDeployScript.run();
        lgeStaking = stakingDeployScript.lgeStaking();

        /// Deploy LGEMigration
        /// @dev not the correct L2 addresses except for wstETH
        l2Addresses = new address[](4);
        l2Addresses[0] = address(usdc);
        l2Addresses[1] = address(usdt);
        l2Addresses[2] = address(1);
        l2Addresses[3] = 0x0733Df3e178c32f44B85B731D5475156a6E16391;

        /// @dev abitrary restricted L2 destinations
        restrictedL2Addresses = new address[](2);
        restrictedL2Addresses[0] = address(1000);
        restrictedL2Addresses[1] = address(1001);

        LGEMigrationDeploy migrationDeployScript = new LGEMigrationDeploy();
        migrationDeployScript.setUp(address(usdxBridge), address(lgeStaking));
        migrationDeployScript.run();
        lgeMigration = migrationDeployScript.lgeMigration();
    }

    /// SETUP ///

    function testInitialize() public view {
        assertEq(address(lgeStaking.lgeMigration()), address(0));
        assertEq(lgeStaking.migrationActivated(), false);

        for (uint256 i; i < 4; i++) {
            assertEq(lgeStaking.allowlisted(l1Addresses[i]), true);
            (i < 2)
                ? assertEq(lgeStaking.depositCap(l1Addresses[i]), 1e12)
                : assertEq(lgeStaking.depositCap(l1Addresses[i]), 1e24);
            assertEq(lgeStaking.totalDeposited(l1Addresses[i]), 0);
        }
    }

    function testDeployRevertWithDuplicateTokens() public {
        /// Duplicate USDC
        l1Addresses = new address[](3);
        l1Addresses[0] = address(usdc);
        l1Addresses[1] = address(usdc);
        l1Addresses[2] = address(dai);
        depositCaps = new uint256[](3);
        depositCaps[0] = 1e30;
        depositCaps[1] = 1e30;
        depositCaps[2] = 1e30;
        vm.expectRevert("LGE Staking: Duplicate tokens.");
        lgeStaking = new LGEStaking(hexTrust, l1Addresses, depositCaps);
    }

    function testDeployRevertWithUnequalArrayLengths() public {
        /// LGE Staking
        l1Addresses = new address[](3);
        l1Addresses[0] = address(usdc);
        l1Addresses[1] = address(usdt);
        l1Addresses[2] = address(dai);
        depositCaps = new uint256[](2);
        depositCaps[0] = 1e30;
        depositCaps[1] = 1e30;
        vm.expectRevert("LGE Staking: Tokens array length must equal the Deposit Caps array length.");
        lgeStaking = new LGEStaking(hexTrust, l1Addresses, depositCaps);

        /// LGE Migration
        vm.expectRevert("LGE Migration: L1 addresses array length must equal the L2 addresses array length.");
        lgeMigration = new LGEMigrationV1(
            hexTrust,
            address(l1StandardBridge),
            address(l1LidoTokensBridge),
            address(usdxBridge),
            address(lgeStaking),
            address(usdc),
            address(wstETH),
            l1Addresses,
            l2Addresses,
            restrictedL2Addresses
        );
    }

    /// DEPOSIT ERC20 ///

    function testDepositERC20FailureConditions() public prank(alice) {
        /// Amount zero
        vm.expectRevert("LGE Staking: May not deposit nothing.");
        lgeStaking.depositERC20(address(usdc), 0);

        /// Not allowlisted
        vm.expectRevert("LGE Staking: Token must be allowlisted.");
        lgeStaking.depositERC20(address(88), 1);

        /// Exceeding deposit caps
        usdc.approve(address(lgeStaking), 1e13);
        vm.expectRevert("LGE Staking: deposit amount exceeds deposit cap.");
        lgeStaking.depositERC20(address(usdc), 1e13);

        vm.stopPrank();
        vm.startPrank(hexTrust);

        /// Fee on transfer
        TestERC20DecimalsFeeOnTransfer feeOnTransferToken = new TestERC20DecimalsFeeOnTransfer(18);
        lgeStaking.setAllowlist(address(feeOnTransferToken), true);
        lgeStaking.setDepositCap(address(feeOnTransferToken), 1e30);
        feeOnTransferToken.mint(hexTrust, 1e21);
        feeOnTransferToken.approve(address(lgeStaking), 1e20);

        vm.expectRevert("LGE Staking: Fee-on-transfer tokens not supported.");
        lgeStaking.depositERC20(address(feeOnTransferToken), 1e20);

        /// Migration activated
        lgeStaking.setMigrationContract(address(lgeMigration));
        assertEq(lgeStaking.migrationActivated(), true);
        vm.stopPrank();
        vm.startPrank(alice);

        vm.expectRevert("LGE Staking: May not deposit once migration has been activated.");
        lgeStaking.depositERC20(address(usdc), 1);
    }

    function testDepositERC20SuccessConditions() public prank(alice) {
        uint256 _amount = 100e6;
        usdc.approve(address(lgeStaking), _amount);

        assertEq(lgeStaking.balance(address(usdc), alice), 0);
        assertEq(lgeStaking.totalDeposited(address(usdc)), 0);
        assertEq(usdc.balanceOf(address(lgeStaking)), 0);

        vm.expectEmit(true, true, true, true);
        emit LGEStaking.Deposit(address(usdc), _amount, alice);
        lgeStaking.depositERC20(address(usdc), _amount);

        assertEq(lgeStaking.balance(address(usdc), alice), _amount);
        assertEq(lgeStaking.totalDeposited(address(usdc)), _amount);
        assertEq(usdc.balanceOf(address(lgeStaking)), _amount);
    }

    /// WITHDRAW ///

    function testWithdrawFailureConditions() public prank(alice) {
        uint256 _amount = 100e6;
        usdc.approve(address(lgeStaking), _amount);
        lgeStaking.depositERC20(address(usdc), _amount);

        /// Amount zero
        vm.expectRevert("LGE Staking: may not withdraw nothing.");
        lgeStaking.withdraw(address(usdc), 0);

        /// Insufficient balance
        vm.expectRevert("LGE Staking: insufficient deposited balance.");
        lgeStaking.withdraw(address(usdc), _amount + 1);
    }

    function testWithdrawSuccessConditions() public prank(alice) {
        uint256 _amount0 = 100e6;
        uint256 _amount1 = 10e6;
        usdc.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(usdc), _amount0);

        assertEq(lgeStaking.balance(address(usdc), alice), _amount0);
        assertEq(lgeStaking.totalDeposited(address(usdc)), _amount0);
        assertEq(usdc.balanceOf(address(lgeStaking)), _amount0);

        vm.expectEmit(true, true, true, true);
        emit LGEStaking.Withdraw(address(usdc), _amount1, alice);
        lgeStaking.withdraw(address(usdc), _amount1);

        assertEq(lgeStaking.balance(address(usdc), alice), _amount0 - _amount1);
        assertEq(lgeStaking.totalDeposited(address(usdc)), _amount0 - _amount1);
        assertEq(usdc.balanceOf(address(lgeStaking)), _amount0 - _amount1);
    }

    /// MIGRATE ///

    function testMigrateFailureConditions() public prank(alice) {
        /// Setup
        uint256 _amount0 = 100e6;

        usdc.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(usdc), _amount0);

        usdt.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(usdt), _amount0);

        dai.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(dai), _amount0);

        /// Only LGE may call
        vm.expectRevert("LGE Migration: Only the staking contract can call this function.");
        lgeMigration.migrate(alice, l1Addresses, depositCaps);

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        /// Migration not active
        vm.expectRevert("LGE Staking: Migration not active.");
        lgeStaking.migrate(alice, tokens);

        /// L2 Destination zero address
        vm.stopPrank();
        vm.startPrank(hexTrust);
        lgeStaking.setMigrationContract(address(lgeMigration));
        assertEq(lgeStaking.migrationActivated(), true);
        vm.stopPrank();
        vm.startPrank(alice);

        vm.expectRevert("LGE Staking: May not send tokens to the zero address.");
        lgeStaking.migrate(address(0), tokens);

        /// Tokens length zero
        tokens = new address[](0);

        vm.expectRevert("LGE Staking: Must migrate some tokens.");
        lgeStaking.migrate(alice, tokens);

        /// No deposits to migrate
        tokens = new address[](1);
        tokens[0] = address(wstETH);

        vm.expectRevert("LGE Staking: No tokens to migrate.");
        lgeStaking.migrate(alice, tokens);

        /// Restricted address recipient
        tokens[0] = address(usdc);

        vm.expectRevert("LGE Migration: L2 address recipient restricted.");
        lgeStaking.migrate(address(1001), tokens);
    }

    function testMigrateSuccessConditions() public prank(alice) {
        /// Setup
        uint256 _amount0 = 100e6;
        usdt.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(usdt), _amount0);

        assertEq(lgeStaking.balance(address(usdt), alice), _amount0);
        assertEq(lgeStaking.totalDeposited(address(usdt)), _amount0);
        assertEq(usdt.balanceOf(address(lgeStaking)), _amount0);

        /// Set Migration
        vm.stopPrank();
        vm.startPrank(hexTrust);
        lgeStaking.setMigrationContract(address(lgeMigration));
        assertEq(lgeStaking.migrationActivated(), true);
        vm.stopPrank();
        vm.startPrank(alice);

        /// Migrate
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdt);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount0;

        vm.expectEmit(true, true, true, true);
        emit LGEStaking.TokensMigrated(alice, alice, tokens, amounts);
        lgeStaking.migrate(alice, tokens);

        assertEq(lgeStaking.balance(address(usdt), alice), 0);
        assertEq(lgeStaking.totalDeposited(address(usdt)), 0);
        assertEq(usdt.balanceOf(address(lgeStaking)), 0);
    }

    function testMigrateSeveralSuccessConditions() public prank(alice) {
        /// Setup
        uint256 _amount0 = 100e6;
        uint256 _amount1 = 100e18;

        usdt.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(usdt), _amount0);

        usdc.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(usdc), _amount0);

        wstETH.approve(address(lgeStaking), _amount1);
        lgeStaking.depositERC20(address(wstETH), _amount1);

        /// Set Migration
        vm.stopPrank();
        vm.startPrank(hexTrust);
        lgeStaking.setMigrationContract(address(lgeMigration));
        assertEq(lgeStaking.migrationActivated(), true);
        vm.stopPrank();
        vm.startPrank(alice);

        /// Migrate
        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);
        tokens[2] = address(wstETH);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _amount0;
        amounts[1] = _amount0;
        amounts[2] = _amount1;

        vm.expectEmit(true, true, true, true);
        emit LGEStaking.TokensMigrated(alice, alice, tokens, amounts);
        lgeStaking.migrate(alice, tokens);

        assertEq(lgeStaking.balance(address(usdt), alice), 0);
        assertEq(lgeStaking.totalDeposited(address(usdt)), 0);
        assertEq(usdt.balanceOf(address(lgeStaking)), 0);
    }

    function testMigrateWSTETHSuccessConditions() public prank(alice) {
        /// Setup
        uint256 _amount0 = 100e18;
        wstETH.approve(address(lgeStaking), _amount0);
        lgeStaking.depositERC20(address(wstETH), _amount0);

        assertEq(lgeStaking.balance(address(wstETH), alice), _amount0);
        assertEq(lgeStaking.totalDeposited(address(wstETH)), _amount0);
        assertEq(wstETH.balanceOf(address(lgeStaking)), _amount0);

        /// Set Migration
        vm.stopPrank();
        vm.startPrank(hexTrust);
        lgeStaking.setMigrationContract(address(lgeMigration));
        assertEq(lgeStaking.migrationActivated(), true);
        vm.stopPrank();
        vm.startPrank(alice);

        /// Migrate
        address[] memory tokens = new address[](1);
        tokens[0] = address(wstETH);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount0;

        vm.expectEmit(true, true, true, true);
        emit LGEStaking.TokensMigrated(alice, alice, tokens, amounts);
        lgeStaking.migrate(alice, tokens);

        assertEq(lgeStaking.balance(address(wstETH), alice), 0);
        assertEq(lgeStaking.totalDeposited(address(wstETH)), 0);
        assertEq(wstETH.balanceOf(address(lgeStaking)), 0);
    }

    function testRecoverTokens() public prank(alice) {
        /// Setup
        uint256 _amount0 = 100e18;
        wstETH.transfer(address(lgeMigration), _amount0);
        assertEq(wstETH.balanceOf(address(lgeMigration)), _amount0);

        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        lgeMigration.recoverTokens(address(wstETH), _amount0, alice);

        vm.stopPrank();
        vm.startPrank(hexTrust);

        /// Recover
        lgeMigration.recoverTokens(address(wstETH), _amount0, alice);
        assertEq(wstETH.balanceOf(address(lgeMigration)), 0);
    }

    function testSetGasLimit() public prank(alice) {
        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        lgeMigration.setGasLimit(address(wstETH), 1e6);

        assertEq(lgeMigration.gasLimits(address(wstETH)), 21000);

        vm.stopPrank();
        vm.startPrank(hexTrust);

        /// Set new gas limit
        lgeMigration.setGasLimit(address(wstETH), 1e6);

        assertEq(lgeMigration.gasLimits(address(wstETH)), 1e6);
    }

    /// OWNER ///

    function testSetAllowlist() public {
        TestERC20Decimals usdd = new TestERC20Decimals(18);
        usdd.mint(alice, 1e18);

        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        lgeStaking.setAllowlist(address(usdd), true);

        /// Owner allowed to set new coin
        vm.startPrank(hexTrust);

        /// Add USDD
        vm.expectEmit(true, true, true, true);
        emit LGEStaking.AllowlistSet(address(usdd), true);
        lgeStaking.setAllowlist(address(usdd), true);

        /// Remove USDC
        vm.expectEmit(true, true, true, true);
        emit LGEStaking.AllowlistSet(address(usdc), false);
        lgeStaking.setAllowlist(address(usdc), false);

        vm.stopPrank();

        assertEq(lgeStaking.allowlisted(address(usdd)), true);
        assertEq(lgeStaking.allowlisted(address(usdc)), false);
    }

    function testSetDepositCap() public {
        uint256 _newCap = 1e24;

        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        lgeStaking.setDepositCap(address(usdc), _newCap);

        assertEq(lgeStaking.depositCap(address(usdc)), 1e12);

        /// Owner allowed
        vm.startPrank(hexTrust);

        vm.expectEmit(true, true, true, true);
        emit LGEStaking.DepositCapSet(address(usdc), _newCap);
        lgeStaking.setDepositCap(address(usdc), _newCap);

        vm.stopPrank();

        assertEq(lgeStaking.depositCap(address(usdc)), _newCap);
    }

    function testSetPaused() public {
        vm.deal(hexTrust, 10000 ether);

        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        lgeStaking.setPaused(true);

        assertEq(lgeStaking.paused(), false);

        /// Owner allowed
        vm.startPrank(hexTrust);

        vm.expectEmit(true, true, true, true);
        emit Pausable.Paused(hexTrust);
        lgeStaking.setPaused(true);

        assertEq(lgeStaking.paused(), true);

        /// External functions paused
        vm.expectRevert("Pausable: paused");
        lgeStaking.depositERC20(address(usdc), 1e18);

        vm.expectRevert("Pausable: paused");
        lgeStaking.withdraw(address(usdc), 1e18);

        address[] memory tokensArray;
        vm.expectRevert("Pausable: paused");
        lgeStaking.migrate(alice, tokensArray);

        vm.expectEmit(true, true, true, true);
        emit Pausable.Unpaused(hexTrust);
        lgeStaking.setPaused(false);

        assertEq(lgeStaking.paused(), false);

        vm.stopPrank();
    }

    function testSetMigrationContract() public {
        address newMigrationContract = address(88);

        /// Non-owner revert
        vm.expectRevert("Ownable: caller is not the owner");
        lgeStaking.setMigrationContract(newMigrationContract);

        assertEq(address(lgeStaking.lgeMigration()), address(0));
        assertEq(lgeStaking.migrationActivated(), false);

        vm.startPrank(hexTrust);

        vm.expectEmit(true, true, true, true);
        emit LGEStaking.MigrationContractSet(newMigrationContract);
        lgeStaking.setMigrationContract(newMigrationContract);

        assertEq(address(lgeStaking.lgeMigration()), newMigrationContract);
        assertEq(lgeStaking.migrationActivated(), true);

        vm.stopPrank();
    }
}
