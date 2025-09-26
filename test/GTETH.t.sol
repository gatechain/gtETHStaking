// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StakingRouter} from "../src/StakingRouter.sol";
import {NodeOperatorsRegistry} from "../src/NodeOperatorsRegistry.sol";
import {INodeOperatorsRegistry} from "../src/interfaces/INodeOperatorsRegistry.sol";
import {IGTETHLocator} from "../src/interfaces/IGTETHLocator.sol";
import {IGTETH} from "../src/interfaces/IGTETH.sol";
import {GTETH} from "../src/GTETH.sol";
import {GTETHLocator} from "../src/GTETHLocator.sol";
import {console} from "forge-std/console.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AccountingOracle} from "../src/oracle/AccountingOracle.sol";


// MOCK deposit contract
contract MockDepositContract {
    event DepositEvent(
        bytes pubkey,
        bytes withdrawal_credentials,
        bytes signature,
        bytes32 deposit_data_root
    );

    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external payable {
        emit DepositEvent(pubkey, withdrawal_credentials, signature, deposit_data_root);
    }
}

contract GTETHTest is Test {
    
    GTETH public gteth;
    AccountingOracle public accountOracle;
    function setUp() public {
        vm.createSelectFork("https://0xrpc.io/hoodi");
        gteth = GTETH(payable(0xA5b68cE84F12c55ACAC70dEbB46A064624951554));
        accountOracle = AccountingOracle(0xAdd4D91Ca960032611D35D7a7d1Df4C3386838E5);

    }

    // function testWithdraw() public {

    //     uint256 amount = 20000000000000000;
    //     vm.prank(0xBd58A0016cc201078EAfA9787B76ba2CA059DA42);
    //     gteth.withdraw(amount);

    // }

    function testSubmitReportData() public {
        console.log("testSubmitReportData");
        accountOracle.getLastProcessingRefSlot();
        accountOracle.getConsensusReport();
       (uint256 refSlot, uint256 reportProcessingDeadlineSlot) = accountOracle.getCurrentFrame();
    //    gteth.yieldData();
       
    //    console.log("refSlot", refSlot);
    //    console.log("reportProcessingDeadlineSlot", reportProcessingDeadlineSlot);
    vm.prank(0x94E4AF739Ec4793f50513AD9436Af809A0E7A4ef);
        address(accountOracle).call(hex"917dd9180000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000012c27f00000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000003427c0d339000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000504dc8cf165e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000001d2e696224d2cf1762c13170084f4e0b6c56d014d4c47decd5158fa69ae2b0de6000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000");
        // console.log("testSubmitReportData done");
    }
}