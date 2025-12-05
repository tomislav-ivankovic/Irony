# Irony

Application that gives it's users the ability to examine T8 situations and inner workings of the T8 game in forensic detail.
The application only works with the PC version of the game.

## Features

- View situations from front, top and side.
- Record situations from practice mode, live games and replays.
- Examine the recorded situations frame by frame.
- Save and open recordings into/from files.
- Examine hit lines, hurt cylinders and collision spheres.
- Measure startup, active and recovery frames as well as the frame advantage.
- Precisely measure attack range, attack height and attack's recovery range.
- Precisely measure distance to opponent, angle to opponent, hit lines height and hurt cylinders height.
- Examine posture, blocking and crushing frame by frame.
- Record suspicious replays and examine player inputs frame by frame.
- Measure any distance you are interested in using the measure tool.

## Quick Video Demonstration

[![Irony - Demonstration](https://img.youtube.com/vi/gzJJUjVC3SY/0.jpg)](https://www.youtube.com/watch?v=gzJJUjVC3SY)

## Installation

### Windows

1. Download the latest release from [here](https://github.com/tomislav-ivankovic/Irony/releases/latest).
2. Extract the `.zip` archive anywhere you want.
3. Run `irony_injector.exe` from the extracted archive.
4. Launch the game using Steam.
5. Once in the game, press `Tab` to open the UI.

(You can also run `irony_injector.exe` after the game already started.)

### Linux

1. Download the latest release from [here](https://github.com/tomislav-ivankovic/Irony/releases/latest).
2. Extract the `.zip` archive anywhere you want.
3. Launch the game using Steam.
4. Use proton to run `irony_injector.exe` with `only_inject` command line argument inside the same Wine prefix that the game is running in:
    - For native Steam installation the command looks something like this:

    ```bash
    STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.local/share/Steam \
    STEAM_COMPAT_DATA_PATH=$HOME/.local/share/Steam/steamapps/compatdata/1778820 \
    WINEPREFIX=$HOME/.local/share/Steam/steamapps/compatdata/1778820/pfx \
    $HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-20/proton run \
    Z:/home/user_name/path_to_irony_folder/irony_injector.exe only_inject
    ```

    - For flatpak Steam installation the command looks something like this:

    ```bash
    flatpak run --command=bash com.valvesoftware.Steam -c '
    STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.var/app/com.valvesoftware.Steam/.steam/root \
    STEAM_COMPAT_DATA_PATH=$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapp/compatdata/1778820 \
    WINEPREFIX=$HOME/.var/app/com.valvesoftware.Steam/.loca/share/Steam/steamapps/compatdata/1778820/pfx \
    $HOME/.var/app/com.valvesoftware.Steam/.steam/roo/compatibilitytools.d/GE-Proton10-20/proton run \
    Z:/home/user_name/path_to_irony_folder/irony_injector.exe only_inject
    '
    ```

    - Modify the command to reflect location of `steamapps` directory you installed the game in, version of proton you are running the game with and location of your Irony directory.
    - Alternatively you can use [Steam Tinker Launch](https://github.com/sonic2kk/steamtinkerlaunch) to launch the injector along with the game.

5. Once injected, press `Tab` to open the UI.

(If you use the above commands to run `irony_injector.exe` before starting the game, the launch will stall, making the game never start up.)

## Building From Source

Take a look inside the [build.zig.zon](./build.zig.zon) file.
Under the property `.zig_version` there is a version of the Zig programming language that the project is to be compiled with.
Install that version of the ZIG compiler onto your machine using the [official Zig tutorial](https://ziglang.org/learn/getting-started).

Make sure that your version of the Zig compiler matches the `.zig_version`, execute:

```bash
zig version
```

To build the project in debug mode set your current directory to the repository root and execute:

```bash
zig build
```

To build the project in release mode execute:

```bash
zig build --release=fast
```

Ether way, after the compilation is over the binaries will be placed inside `zig-out/bin`.

To run the application while developing execute:

```bash
zig build run
```

To run the project's tests execute:

```bash
zig build test
```

If you are on Linux, the tests will run inside Wine.
Make sure you have Wine installed and make sure that your default Wine prefix has `dxvk` and `vkd3d` installed.
You can use the following command to install these:

```bash
winetricks dxvk vkd3d
```

## Not Open Source

While this application is free to download and it's source code is publicly available for inspection, the license that the code is under limits the legal rights of the public in a way that makes this software NOT open source.
A more accurate way to describe this software is "source-available".
For more details look at the [license](./LICENSE.md).

## Support

To support me and this project you can donate using one of the following links:

- [One Time Donation](https://donate.stripe.com/5kQ8wI2qi1zbdWkgUPao800)
- [Recurring Donation](https://donate.stripe.com/fZu4gsd4W0v77xWeMHao801)

Additionally.
If you are recruiting software developers, and you like what you see here, you can offer me a job by contacting me via email: [jobs@tomislav-ivankovic.from.hr](mailto:jobs@tomislav-ivankovic.from.hr)
