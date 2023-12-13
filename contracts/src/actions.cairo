//---------------------------------------------------------------------------------------------
// *Actions Contract*
// This contract handles all the actions that can be performed by the user
// Typically you group functions that require similar authentication into a single contract
// For this demo we are keeping all the functions in a single contract
//---------------------------------------------------------------------------------------------

#[dojo::contract]
mod actions {
    use starknet::{ContractAddress, get_caller_address};
    use debug::PrintTrait;
    use cubit::f128::procgen::simplex3;
    use cubit::f128::types::fixed::FixedTrait;
    use cubit::f128::types::vec3::Vec3Trait;

    // import actions
    use emojiman::interface::IActions;

    // import models
    use emojiman::models::{
        GAME_DATA_KEY, GameData, Direction, Vec2, Position, PlayerAtPosition,
        PlayerID, PlayerAddress
    };

    // import utils
    use emojiman::utils::next_position;

    // import config
    use emojiman::config::{
        X_RANGE, Y_RANGE, ORIGIN_OFFSET
    };

    // import integer
    use integer::{u128s_from_felt252, U128sFromFelt252Result, u128_safe_divmod};

    // resource of world
    const DOJO_WORLD_RESOURCE: felt252 = 0;

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // --------- EXTERNALS -------------------------------------------------------------------------
    // These functions are called by the user and are exposed to the public
    // ---------------------------------------------------------------------------------------------

    // impl: implement functions specified in trait
    #[external(v0)]
    impl ActionsImpl of IActions<ContractState> {
        // Spawns the player on to the map
        fn spawn(self: @ContractState) {
            // world dispatcher
            let world = self.world_dispatcher.read();

            // player address
            let player = get_caller_address();

            // game data
            let mut game_data = get!(world, GAME_DATA_KEY, (GameData));

            // increment player count
            game_data.number_of_players += 1;

            // NOTE: save game_data model with the set! macro
            set!(world, (game_data));

            // get player id 
            let mut player_id = get!(world, player, (PlayerID)).id;

            // if player id is 0, assign new id
            if player_id == 0 {
                // Player not already spawned, prepare ID to assign
                player_id = assign_player_id(world, game_data.number_of_players, player);
            } else {
                // Player already exists, clear old position for new spawn
                let pos = get!(world, player_id, (Position));
                clear_player_at_position(world, pos.x, pos.y);
            }

            // spawn on random position
            let (x, y) = spawn_coords(world, player.into(), player_id.into());

            // set player position
            player_position(world, player_id, x, y);
        }

        // Queues move for player to be processed later
        fn move(self: @ContractState, dir: Direction) {
            // world dispatcher
            let world = self.world_dispatcher.read();

            // player address
            let player = get_caller_address();

            // player id
            let id = get!(world, player, (PlayerID)).id;

            // player position
            let pos = get!(world, id, Position);

            // Clear old position
            clear_player_at_position(world, pos.x, pos.y);

            // Get new position
            let Position{id, x, y } = next_position(pos, dir);

            // Get max x and y
            let max_x: felt252 = ORIGIN_OFFSET.into() + X_RANGE.into();
            let max_y: felt252 = ORIGIN_OFFSET.into() + Y_RANGE.into();

            // assert max x and y
            assert(
                x <= max_x.try_into().unwrap() && y <= max_y.try_into().unwrap(), 'Out of bounds'
            );

            let adversary = player_at_position(world, x, y);
            assert(adversary == 0, 'Cell occupied');

            player_position(world, id, x, y);
        }

        // ----- ADMIN FUNCTIONS -----
        // These functions are only callable by the owner of the world
        fn cleanup(self: @ContractState) {
            let world = self.world_dispatcher.read();
            let player = get_caller_address();

            assert(
                world.is_owner(get_caller_address(), DOJO_WORLD_RESOURCE), 'only owner can call'
            );

            // reset player count
            let mut game_data = get!(world, GAME_DATA_KEY, (GameData));
            game_data.number_of_players = 0;
            set!(world, (game_data));

            // Kill off all players
            let mut i = 1;
            loop {
                if i > 20 {
                    break;
                }
                player_dead(world, i);
                i += 1;
            };
        }
    }

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // --------- INTERNALS -------------------------------------------------------------------------
    // These functions are called by the contract and are not exposed to the public
    // ---------------------------------------------------------------------------------------------

    // @dev: 
    // 1. Assigns player id
    // 2. Sets player address
    // 3. Sets player id
    fn assign_player_id(world: IWorldDispatcher, num_players: u8, player: ContractAddress) -> u8 {
        let id = num_players;
        set!(world, (PlayerID { player, id }, PlayerAddress { player, id }));
        id
    }

    // @dev: Sets no player at position
    fn clear_player_at_position(world: IWorldDispatcher, x: u8, y: u8) {
        set!(world, (PlayerAtPosition { x, y, id: 0 }));
    }

    // @dev: Returns player id at position
    fn player_at_position(world: IWorldDispatcher, x: u8, y: u8) -> u8 {
        get!(world, (x, y), (PlayerAtPosition)).id
    }

    // @dev: Sets player position
    fn player_position(world: IWorldDispatcher, id: u8, x: u8, y: u8) {
        set!(world, (PlayerAtPosition { x, y, id }, Position { x, y, id }));
    }

    // @dev: Kills player
    fn player_dead(world: IWorldDispatcher, id: u8) {
        let pos = get!(world, id, (Position));
        let empty_player = starknet::contract_address_const::<0>();

        let id_felt: felt252 = id.into();
        let entity_keys = array![id_felt].span();
        let player = get!(world, id, (PlayerAddress)).player;
        let player_felt: felt252 = player.into();
        // Remove player address and ID mappings

        let mut layout = array![];

        world.delete_entity('PlayerID', array![player_felt].span(), layout.span());
        world.delete_entity('PlayerAddress', entity_keys, layout.span());

        set!(world, (PlayerID { player, id: 0 }));
        set!(world, (Position { id, x: 0, y: 0 }));

        // Remove player components
        world.delete_entity('Position', entity_keys, layout.span());
    }

    // @dev: Returns random spawn coordinates
    fn spawn_coords(world: IWorldDispatcher, player: felt252, mut salt: felt252) -> (u8, u8) {
        let mut x = 10;
        let mut y = 10;
        loop {
            let hash = pedersen::pedersen(player, salt);
            let rnd_seed = match u128s_from_felt252(hash) {
                U128sFromFelt252Result::Narrow(low) => low,
                U128sFromFelt252Result::Wide((high, low)) => low,
            };
            let (rnd_seed, x_) = u128_safe_divmod(rnd_seed, X_RANGE.try_into().unwrap());
            let (rnd_seed, y_) = u128_safe_divmod(rnd_seed, Y_RANGE.try_into().unwrap());
            let x_: felt252 = x_.into();
            let y_: felt252 = y_.into();

            x = ORIGIN_OFFSET + x_.try_into().unwrap();
            y = ORIGIN_OFFSET + y_.try_into().unwrap();
            let occupied = player_at_position(world, x, y);
            if occupied == 0 {
                break;
            } else {
                salt += 1; // Try new salt
            }
        };
        (x, y)
    }
}

#[cfg(test)]
mod tests {
    use debug::PrintTrait;
    use array::{Array, ArrayTrait};

    #[test]
    #[available_gas(30000000)]
    fn test_cc() {
        let mut list: Array<felt252> = ArrayTrait::new();
        list.append(1);
        let address = starknet::contract_address_const::<0x056834208d6a7cc06890a80ce523b5776755d68e960273c9ef3659b5f74fa494>();
        let method = 'generate_dungeon';
        let res = starknet::call_contract_syscall(address, method, list.span());
        res.unwrap();
    }
}
