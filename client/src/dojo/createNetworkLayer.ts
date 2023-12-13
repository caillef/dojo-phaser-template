import { world } from "./world";
import { setup } from "./setup";
import { createSyncManager } from "@dojoengine/react";

export type NetworkLayer = Awaited<ReturnType<typeof createNetworkLayer>>;

export const createNetworkLayer = async () => {
    const { components, systemCalls, network } = await setup();

    const { Position, PlayerID, PlayerAddress } =
        network.contractComponents;

    const { burnerManager, toriiClient, account } = network;

    // @dev: This is a hack as we have to manually add entities to the world in order to sync.
    // this is updated in 0.4.0 into a single line and syncs all the world.
    // TODO: remove in 0.4.0
    const initial_sync = () => {
        const models: any = [];

        for (let i = 1; i <= 30; i++) {
            let keys = [BigInt(i)];
            models.push({
                model: Position,
                keys,
            });
            models.push({
                model: PlayerAddress,
                keys,
            });
        }

        models.push({
            model: PlayerID,
            keys: [BigInt(account.address)],
        });

        return models;
    };

    const { sync } = createSyncManager(toriiClient, initial_sync());

    sync();

    return {
        world,
        components,
        systemCalls,
        network,
        account,
        burnerManager,
    };
};
