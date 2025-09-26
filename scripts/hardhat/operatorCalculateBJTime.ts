const genesisTime = 1742213400;
const slotDuration = 12;
const targetSlot = 1028543;

const timestamp = genesisTime + targetSlot * slotDuration;

const beijingTime = new Date(timestamp * 1000).toLocaleString("zh-CN", {
  timeZone: "Asia/Shanghai",
});

console.log("北京时间为:", beijingTime);
