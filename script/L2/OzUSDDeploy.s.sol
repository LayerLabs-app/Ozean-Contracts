// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ScriptUtils, console} from "script/utils/ScriptUtils.sol";
import {OzUSD, IERC20} from "src/L2/OzUSD.sol";

contract OzUSDDeploy is ScriptUtils {
    OzUSD public ozUSD;

    function run() external payable broadcast {
        /// Environment Vars
        address hexTrust;
        address l2USDX;
        uint256 initialSharesAmount;
        if (block.chainid == 1) {
            hexTrust = vm.envAddress("ADMIN");
            l2USDX = vm.envAddress("L2_MAINNET_USDX");
            initialSharesAmount = vm.envUint("INITIAL_SHARE_AMOUNT");
        } else if (block.chainid == 31911) {
            hexTrust = vm.envAddress("ADMIN");
            l2USDX = vm.envAddress("L2_SEPOLIA_USDX");
            initialSharesAmount = vm.envUint("INITIAL_SHARE_AMOUNT");
        } else {
            revert();
        }
        require(hexTrust != address(0), "Script: Zero address.");
        require(l2USDX != address(0), "Script: Zero address.");
        require(initialSharesAmount == 1e18, "Script: Zero amount.");
        /// Approve
        address predictedAddress = _addressFrom(hexTrust, 12);
        IERC20(l2USDX).approve(predictedAddress, 1e18);
        /// Deploy
        bytes memory deployData = abi.encode(hexTrust, l2USDX, initialSharesAmount);
        console.logBytes(deployData);
        ozUSD = new OzUSD(hexTrust, l2USDX, initialSharesAmount);
        /// Post-deploy checks
        require(address(ozUSD) == predictedAddress, "Script: Wrong Predicted Address.");
        require(IERC20(l2USDX).balanceOf(address(ozUSD)) == initialSharesAmount, "Script: Initial supply.");
        require(ozUSD.balanceOf(address(0xdead)) == initialSharesAmount, "Script: Initial supply.");
        require(address(ozUSD.usdx()) == l2USDX, "Script: Wrong address.");
    }
}
