// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ILGEMigration} from "./interface/ILGEMigration.sol";

/// @title  LGE Migration V1
/// @notice This contract facilitates the migration of staked tokens from the LGE Staking pool
///         on Layer 1 to the Ozean Layer 2.
contract LGEMigrationV1 is ILGEMigration, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The standard bridge contract for Layer 1 to Layer 2 transfers.
    IL1StandardBridge public immutable l1StandardBridge;

    /// @notice The address of the LGE Staking contract.
    address public immutable lgeStaking;

    /// @notice A mapping from Layer 1 token addresses to their corresponding Layer 2 addresses.
    mapping(address => address) public l1ToL2Addresses;

    constructor(
        address _l1StandardBridge,
        address _lgeStaking,
        address[] memory _l1Addresses,
        address[] memory _l2Addresses
    ) {
        l1StandardBridge = IL1StandardBridge(_l1StandardBridge);
        lgeStaking = _lgeStaking;
        uint256 length = _l1Addresses.length;
        require(
            length == _l2Addresses.length,
            "LGE Migration: L1 addresses array length must equal the L2 addresses array length."
        );
        for (uint256 i; i < length; ++i) {
            l1ToL2Addresses[_l1Addresses[i]] = _l2Addresses[i];
        }
    }

    /// @notice This function is called by the LGE Staking contract to facilitate migration of staked tokens from
    ///         the LGE Staking pool to the Ozean L2.
    /// @param _l2Destination The address which will be credited the tokens on Ozean.
    /// @param _tokens The tokens being migrated to Ozean from the LGE Staking contract.
    /// @param _amounts The amounts of each token to be migrated to Ozean for the _user
    function migrate(address _l2Destination, address[] calldata _tokens, uint256[] calldata _amounts)
        external
        nonReentrant
    {
        require(msg.sender == lgeStaking, "LGE Migration: Only the staking contract can call this function.");

        /// @dev need to account for USDC => USDX, and wstETH

        uint256 length = _tokens.length;
        for (uint256 i; i < length; i++) {
            require(
                l1ToL2Addresses[_tokens[i]] != address(0), "LGE Migration: L2 contract address not set for migration."
            );
            IERC20(_tokens[i]).approve(address(l1StandardBridge), _amounts[i]);
            l1StandardBridge.depositERC20To(
                _tokens[i], l1ToL2Addresses[_tokens[i]], _l2Destination, _amounts[i], 21000, ""
            );
        }
    }
}

interface IL1StandardBridge {
    /// @custom:legacy
    /// @notice Deposits some amount of ERC20 tokens into a target account on L2.
    /// @param _l1Token     Address of the L1 token being deposited.
    /// @param _l2Token     Address of the corresponding token on L2.
    /// @param _to          Address of the recipient on L2.
    /// @param _amount      Amount of the ERC20 to deposit.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2.
    ///                     Data supplied here will not be used to execute any code on L2 and is
    ///                     only emitted as extra data for the convenience of off-chain tooling.
    function depositERC20To(
        address _l1Token,
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}
