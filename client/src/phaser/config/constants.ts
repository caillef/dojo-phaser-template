export enum Scenes {
    Main = "Main",
}

export enum Maps {
    Main = "Main",
}

export enum Animations {
    SoldierIdle = "SoldierIdle",
}

// image addresses

export enum Sprites {
    Soldier,
}

export const ImagePaths: { [key in Sprites]: string } = {
    [Sprites.Soldier]: "rock.png",
};

export enum Assets {
    MainAtlas = "MainAtlas",
    Tileset = "Tileset",
}

export enum Direction {
    Unknown,
    Up,
    Down,
    Left,
    Right,
}

export const TILE_HEIGHT = 32;
export const TILE_WIDTH = 32;

// contract offset so we don't overflow
export const ORIGIN_OFFSET = 100;
