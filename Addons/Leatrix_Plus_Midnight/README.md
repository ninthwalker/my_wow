# Leatrix_Plus.lua modified for midnight intro/silvermoon up to Fairbreeze 

Leatrix already works for single gossip and 1 quest reward options. The lua file was extended to include the following specific use cases for midnight intro leveling:  

## Gossip selection
Adds the specific gossip options for the following. Only occurs if below level 81.
- Image of Lady Liadrin
- Arator
- Lor'themar Theron
- Banker
- Skymaster
- Valeera Sanguinar
- Innkeeper (click npc once for quest, then again to auto-set hearthstone)  

# Quest completion
Occurs while under level 81
- Rewards: Currently selects the 1st option all the time if 3 or less rewards

## Instructions:
1. make a copy of the current Leatrix_Plus.lua to restore later if needed.
2. copy the  `Leatrix_Plus.lua ` file from this repo and place where the current file resides in your Leatrix_Plus addon folder.
> Note that updating the addon via curse/etc will overwrite this modded leatrix file and you will need to copy this file back into the directory again.
