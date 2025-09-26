# 项目框架采取foundry 集成 hardhat 的形式

🔑 环境变量
复制 env.example 到 .env，填入参数

🧪 测试
Hardhat 测试
npx hardhat test

Foundry 测试
forge test

Hardhat 脚本调用
npx hardhat run scripts/vaultCheck.ts --network arbitrum-sepolia

🔍 调试 & 查询
Foundry cast
# 查询合约方法
cast call $VAULT_ADDRESS "paused()(bool)" --rpc-url $RPC_URL

# 调用带参数方法
cast call $ADDRESS "getBalancesWithTokens(bytes32,bytes32[])(tuple(bytes32,int128,uint128)[])" xxx --rpc-url $RPC_URL
# gtETHStaking
