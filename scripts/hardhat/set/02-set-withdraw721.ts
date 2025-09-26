import { ethers, upgrades } from "hardhat";
import { WithdrawalQueueERC721 } from "../../../typechain-types";
import {
  updateContractDeployment,
  getContractDeployment,
} from "../utils/deploymentUtils";

async function main() {
  const withdrawalQueueERC721 = await getContractDeployment(
    "WithdrawalQueueERC721"
  );
  if (!withdrawalQueueERC721?.proxy) {
    throw new Error("WithdrawalQueueERC721 is not deployed");
  }

  const gteth = await getContractDeployment("GTETH");
  if (!gteth?.proxy) {
    throw new Error("GTETH is not deployed");
  }

  const withdrawalQueueERC721Proxy = <WithdrawalQueueERC721>(
    await ethers.getContractAt(
      "WithdrawalQueueERC721",
      withdrawalQueueERC721.proxy
    )
  );

  const requestRole =
    await withdrawalQueueERC721Proxy.WITHDRAWAL_REQUEST_ROLE();
  const finalizeRole =
    await withdrawalQueueERC721Proxy.WITHDRAWAL_FINALIZE_ROLE();
  const claimRole = await withdrawalQueueERC721Proxy.WITHDRAWAL_CLAIM_ROLE();

  let hasRole = await withdrawalQueueERC721Proxy.hasRole(
    requestRole,
    gteth.proxy
  );
  if (!hasRole) {
    console.log("Setting WithdrawalQueueERC721 request role");
    await withdrawalQueueERC721Proxy.grantRole(requestRole, gteth.proxy);
  } else {
    console.log("WithdrawalQueueERC721 request role is already set");
  }

  hasRole = await withdrawalQueueERC721Proxy.hasRole(finalizeRole, gteth.proxy);
  if (!hasRole) {
    console.log("Setting WithdrawalQueueERC721 finalize role");
    await withdrawalQueueERC721Proxy.grantRole(finalizeRole, gteth.proxy);
  } else {
    console.log("WithdrawalQueueERC721 finalize role is already set");
  }

  hasRole = await withdrawalQueueERC721Proxy.hasRole(claimRole, gteth.proxy);
  if (!hasRole) {
    console.log("Setting WithdrawalQueueERC721 claim role");
    await withdrawalQueueERC721Proxy.grantRole(claimRole, gteth.proxy);
  } else {
    console.log("WithdrawalQueueERC721 claim role is already set");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
