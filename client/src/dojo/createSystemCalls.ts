import { SetupNetworkResult } from "./setupNetwork";
import { ClientComponents } from "./createClientComponents";
import { MoveSystemProps, SpawnSystemProps } from "./types";
import { uuid } from "@latticexyz/utils";
import { Entity, getComponentValue } from "@dojoengine/recs";
import { getEntityIdFromKeys } from "@dojoengine/utils";
import { updatePositionWithDirection } from "./utils";

export type SystemCalls = ReturnType<typeof createSystemCalls>;

export function createSystemCalls(
    { execute }: SetupNetworkResult,
    { Position, PlayerID }: ClientComponents
) {
    const spawn = async (props: SpawnSystemProps) => {
        try {
            await execute(props.signer, "actions", "spawn", []);
        } catch (e) {
            console.error(e);
        }
    };

    const move = async (props: MoveSystemProps) => {
        const { signer, direction } = props;

        // get player ID
        const playerID = getEntityIdFromKeys([
            BigInt(signer.address),
        ]) as Entity;

        // get the ID associated with the PlayerID
        const entityId = getComponentValue(PlayerID, playerID)?.id;

        // get the entity
        const playerEntity = getEntityIdFromKeys([
            BigInt(entityId?.toString() || "0"),
        ]);

        // get the position
        const position = getComponentValue(Position, playerEntity);

        // update the position with the direction
        const new_position = updatePositionWithDirection(
            direction,
            position || { x: 0, y: 0 }
        );

        // add an override to the position
        const positionId = uuid();
        Position.addOverride(positionId, {
            entity: playerEntity,
            value: { id: entityId, x: new_position.x, y: new_position.y },
        });

        try {
            const { transaction_hash } = await execute(
                signer,
                "actions",
                "move",
                [direction]
            );

            // logging the transaction hash
            // console.log(
            //     await signer.waitForTransaction(transaction_hash, {
            //         retryInterval: 100,
            //     })
            // );

            // just wait until indexer sync - currently ~1 second.
            // TODO: v0.4.0 will resolve to indexer
            await new Promise((resolve) => setTimeout(resolve, 1000));
        } catch (e) {
            console.log(e);
            Position.removeOverride(positionId);
        } finally {
            Position.removeOverride(positionId);
        }
    };

    return {
        spawn,
        move,
    };
}
